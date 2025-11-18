# 注册系统改进实施指南

本文档提供详细的分步实施指南，用于改进注册系统的业务逻辑。

---

## 📋 改进概述

### 当前问题
1. **m2_users 创建时机不当**：注册时立即创建，导致未验证用户产生冗余数据
2. **缺少用户名注册**：用户无法自定义用户名，只能使用邮箱
3. **没有用户名重复检查**：前端无法提前验证用户名可用性

### 解决方案
1. ✅ 修改为**邮箱验证后**才创建 m2_users 记录
2. ✅ 添加**用户名注册功能**（前端 + 后端）
3. ✅ 实现**实时用户名可用性检查**
4. ✅ 提供**数据清理工具**

---

## 🚀 实施步骤

### 第一阶段：数据库改进

#### Step 1: 备份数据库
```bash
# 通过 Supabase Dashboard 创建备份
# 或使用 pg_dump（如果有直接访问权限）
```

#### Step 2: 查看当前状态
在 Supabase SQL Editor 执行：

```sql
-- 查看未验证用户统计
SELECT 
    COUNT(*) FILTER (WHERE email_confirmed_at IS NULL) AS unverified_users,
    COUNT(*) FILTER (WHERE email_confirmed_at IS NOT NULL) AS verified_users,
    COUNT(*) AS total_users
FROM auth.users;

-- 查看有 m2_users 记录但未验证的用户
SELECT COUNT(*) AS unverified_with_m2_users
FROM auth.users au
INNER JOIN m2_users mu ON mu.id = au.id
WHERE au.email_confirmed_at IS NULL;
```

#### Step 3: 执行改进脚本
在 Supabase SQL Editor 中执行：

```sql
-- 执行 cc2055/travel-supabase-schema-v3-improved.sql
-- 该脚本会：
-- 1. 替换 fn_create_user_profile() 函数
-- 2. 更新触发器
-- 3. 添加辅助函数
```

#### Step 4: 验证触发器更新
```sql
-- 查看触发器是否正确更新
SELECT 
    trigger_name, 
    event_manipulation, 
    event_object_table,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'trg_auth_users_create_profile';
```

#### Step 5: 清理现有数据（可选）
```sql
-- 查看统计
SELECT * FROM fn_get_unverified_users_stats();

-- 选项 A: 删除未验证用户的 m2_users 记录（保留 auth.users）
SELECT fn_remove_m2_users_for_unverified();

-- 选项 B: 完全删除 30 天以上未验证的用户
SELECT * FROM fn_cleanup_unverified_users(30);
```

#### Step 6: 测试数据库触发器
```sql
-- 1. 创建一个未验证的测试用户
INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data,
    created_at,
    updated_at
) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    'test_unverified@example.com',
    crypt('password123', gen_salt('bf')),
    NULL,  -- 未验证
    '{"username": "testuser123"}'::jsonb,
    NOW(),
    NOW()
) RETURNING id;

-- 2. 检查 m2_users，应该没有记录
SELECT * FROM m2_users WHERE id = '<上面返回的 id>';

-- 3. 模拟邮箱验证
UPDATE auth.users
SET email_confirmed_at = NOW()
WHERE email = 'test_unverified@example.com';

-- 4. 再次检查 m2_users，应该有记录了
SELECT * FROM m2_users WHERE username = 'testuser123';

-- 5. 清理测试数据
DELETE FROM auth.users WHERE email = 'test_unverified@example.com';
```

---

### 第二阶段：后端 API 改进

#### Step 1: 创建用户名检查 API

创建文件 `src/app/api/auth/check-username/route.ts`:

```typescript
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import type { ApiResponse } from '@/types'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const username = searchParams.get('username')

    if (!username) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: '用户名不能为空',
      })
    }

    // 验证用户名格式
    if (username.length < 3 || username.length > 30) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: '用户名长度必须在 3-30 个字符之间',
      })
    }

    // 验证用户名格式（只允许字母、数字、下划线）
    const usernameRegex = /^[a-zA-Z0-9_]+$/
    if (!usernameRegex.test(username)) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: '用户名只能包含字母、数字和下划线',
      })
    }

    // 检查用户名是否已存在
    const { data, error } = await supabaseAdmin
      .from('m2_users')
      .select('username')
      .ilike('username', username)
      .single()

    if (error && error.code !== 'PGRST116') {
      // PGRST116 = No rows found
      console.error('Check username error:', error)
      return NextResponse.json<ApiResponse>({
        success: false,
        error: '检查用户名时出错',
      })
    }

    const available = !data
    return NextResponse.json<ApiResponse>({
      success: true,
      data: {
        available,
        message: available ? '用户名可用' : '用户名已被占用',
      },
    })
  } catch (error) {
    console.error('Check username error:', error)
    return NextResponse.json<ApiResponse>(
      { success: false, error: '服务器错误' },
      { status: 500 }
    )
  }
}
```

#### Step 2: 更新注册 API

修改 `src/app/api/auth/register/route.ts`:

```typescript
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import type { ApiResponse } from '@/types'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(request: NextRequest) {
  try {
    const { email, username, password, role = 'user' } = await request.json()

    // 验证必填字段
    if (!email || !password) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '邮箱和密码不能为空' },
        { status: 400 }
      )
    }

    // 验证用户名（如果提供）
    if (username) {
      // 验证用户名长度
      if (username.length < 3 || username.length > 30) {
        return NextResponse.json<ApiResponse>(
          { success: false, error: '用户名长度必须在 3-30 个字符之间' },
          { status: 400 }
        )
      }

      // 验证用户名格式
      const usernameRegex = /^[a-zA-Z0-9_]+$/
      if (!usernameRegex.test(username)) {
        return NextResponse.json<ApiResponse>(
          { success: false, error: '用户名只能包含字母、数字和下划线' },
          { status: 400 }
        )
      }

      // 检查用户名是否已存在
      const { data: existingUser } = await supabaseAdmin
        .from('m2_users')
        .select('username')
        .ilike('username', username)
        .single()

      if (existingUser) {
        return NextResponse.json<ApiResponse>(
          { success: false, error: '用户名已被占用，请选择其他用户名' },
          { status: 400 }
        )
      }
    }

    // 创建用户
    const { data: authData, error: signUpError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: false, // 需要邮箱验证
      user_metadata: {
        role,
        username: username || null,
      },
    })

    if (signUpError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: signUpError.message },
        { status: 400 }
      )
    }

    if (!authData.user) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '创建用户失败' },
        { status: 500 }
      )
    }

    // 注意：m2_users 记录会在邮箱验证后由触发器自动创建
    // 不再需要手动插入 profiles

    return NextResponse.json<ApiResponse>(
      {
        success: true,
        message: '注册成功！请检查您的邮箱以验证账号。',
        data: { 
          userId: authData.user.id,
          email: authData.user.email,
        },
      },
      { status: 201 }
    )
  } catch (error) {
    console.error('Registration error:', error)
    return NextResponse.json<ApiResponse>(
      { success: false, error: '服务器错误，请稍后再试' },
      { status: 500 }
    )
  }
}
```

#### Step 3: 更新类型定义

修改 `src/types/index.ts`:

```typescript
// 找到 RegisterFormData 并添加 username
export interface RegisterFormData {
  email: string
  username?: string  // 新增：可选用户名
  password: string
  confirmPassword: string
  role: 'user' | 'author'
}

// 添加用户名检查响应类型
export interface UsernameCheckResponse {
  available: boolean
  message: string
}
```

---

### 第三阶段：前端改进

#### Step 1: 更新注册表单

修改 `src/app/(auth)/register/page.tsx`:

```typescript
'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { toast } from 'sonner'
import type { RegisterFormData, UsernameCheckResponse } from '@/types'

export default function RegisterPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [checkingUsername, setCheckingUsername] = useState(false)
  const [usernameStatus, setUsernameStatus] = useState<{
    available: boolean | null
    message: string
  }>({ available: null, message: '' })
  
  const [formData, setFormData] = useState<RegisterFormData>({
    email: '',
    username: '',
    password: '',
    confirmPassword: '',
    role: 'user',
  })

  // 防抖检查用户名
  useEffect(() => {
    const username = formData.username?.trim()
    
    if (!username || username.length < 3) {
      setUsernameStatus({ available: null, message: '' })
      return
    }

    const timeoutId = setTimeout(async () => {
      setCheckingUsername(true)
      try {
        const response = await fetch(`/api/auth/check-username?username=${encodeURIComponent(username)}`)
        const data = await response.json()
        
        if (data.success) {
          setUsernameStatus({
            available: data.data.available,
            message: data.data.message,
          })
        } else {
          setUsernameStatus({
            available: false,
            message: data.error || '检查失败',
          })
        }
      } catch (error) {
        console.error('Check username error:', error)
      } finally {
        setCheckingUsername(false)
      }
    }, 500) // 500ms 防抖

    return () => clearTimeout(timeoutId)
  }, [formData.username])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value })
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)

    // 验证密码
    if (formData.password !== formData.confirmPassword) {
      toast.error('两次密码输入不一致')
      setLoading(false)
      return
    }

    if (formData.password.length < 6) {
      toast.error('密码长度至少为 6 位')
      setLoading(false)
      return
    }

    // 验证用户名可用性
    if (formData.username && usernameStatus.available === false) {
      toast.error('用户名已被占用，请选择其他用户名')
      setLoading(false)
      return
    }

    try {
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: formData.email,
          username: formData.username || undefined,
          password: formData.password,
          role: formData.role,
        }),
      })

      const data = await response.json()

      if (data.success) {
        toast.success(data.message)
        router.push('/verify-email?email=' + encodeURIComponent(formData.email))
      } else {
        toast.error(data.error || '注册失败')
      }
    } catch (error) {
      console.error('Register error:', error)
      toast.error('注册失败，请稍后再试')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100">
      <Card className="w-full max-w-md mx-4">
        <CardHeader>
          <CardTitle>创建账号</CardTitle>
          <CardDescription>填写以下信息注册新账号</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">邮箱地址 *</Label>
              <Input
                id="email"
                name="email"
                type="email"
                placeholder="your@email.com"
                value={formData.email}
                onChange={handleChange}
                required
              />
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="username">
                用户名 (可选)
                {checkingUsername && (
                  <span className="text-xs text-muted-foreground ml-2">检查中...</span>
                )}
              </Label>
              <Input
                id="username"
                name="username"
                type="text"
                placeholder="3-30个字符，字母数字下划线"
                value={formData.username}
                onChange={handleChange}
                minLength={3}
                maxLength={30}
              />
              {usernameStatus.message && (
                <p className={`text-xs ${
                  usernameStatus.available 
                    ? 'text-green-600' 
                    : 'text-red-600'
                }`}>
                  {usernameStatus.message}
                </p>
              )}
              <p className="text-xs text-muted-foreground">
                留空将使用邮箱前缀作为用户名
              </p>
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">密码 *</Label>
              <Input
                id="password"
                name="password"
                type="password"
                placeholder="至少 6 位字符"
                value={formData.password}
                onChange={handleChange}
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="confirmPassword">确认密码 *</Label>
              <Input
                id="confirmPassword"
                name="confirmPassword"
                type="password"
                placeholder="再次输入密码"
                value={formData.confirmPassword}
                onChange={handleChange}
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="role">账号类型</Label>
              <select
                id="role"
                name="role"
                value={formData.role}
                onChange={handleChange}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              >
                <option value="user">普通用户</option>
                <option value="author">作者</option>
              </select>
            </div>

            <Button type="submit" className="w-full" disabled={loading || checkingUsername}>
              {loading ? '注册中...' : '注册'}
            </Button>

            <p className="text-center text-sm text-muted-foreground">
              已有账号？{' '}
              <Link href="/login" className="text-primary hover:underline">
                立即登录
              </Link>
            </p>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
```

---

## ✅ 测试清单

### 数据库测试
- [ ] 触发器已正确更新
- [ ] 注册未验证用户时不创建 m2_users 记录
- [ ] 验证邮箱后自动创建 m2_users 记录
- [ ] 用户名冲突时自动添加后缀
- [ ] 清理函数正常工作

### API 测试
- [ ] 用户名检查 API 正常工作
- [ ] 短于 3 字符的用户名被拒绝
- [ ] 重复用户名被拒绝
- [ ] 特殊字符用户名被拒绝
- [ ] 注册 API 正确传递 username

### 前端测试
- [ ] 用户名输入框显示正常
- [ ] 实时检查用户名可用性
- [ ] 防抖功能正常（输入停止 500ms 后才检查）
- [ ] 显示用户名可用/不可用提示
- [ ] 可选留空用户名
- [ ] 表单验证正常

### 集成测试
- [ ] 完整注册流程：注册 → 验证邮箱 → 创建 m2_users
- [ ] 不验证邮箱时没有 m2_users 记录
- [ ] 自定义用户名注册成功
- [ ] 留空用户名时自动生成
- [ ] 邮箱重复注册被拒绝

---

## 🔧 故障排除

### 问题 1: 触发器没有触发
```sql
-- 检查触发器是否存在
SELECT * FROM pg_trigger WHERE tgname = 'trg_auth_users_create_profile';

-- 重新创建触发器
DROP TRIGGER IF EXISTS trg_auth_users_create_profile ON auth.users;
CREATE TRIGGER trg_auth_users_create_profile
    AFTER INSERT OR UPDATE OF email_confirmed_at ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION fn_create_user_profile();
```

### 问题 2: 用户名检查 API 404
```bash
# 确认文件路径正确
ls -la src/app/api/auth/check-username/route.ts

# 重启开发服务器
npm run dev
```

### 问题 3: 邮箱验证后仍没有 m2_users 记录
```sql
-- 检查 auth.users 的 email_confirmed_at 字段
SELECT id, email, email_confirmed_at, created_at 
FROM auth.users 
WHERE email = 'your@email.com';

-- 手动触发（测试用）
UPDATE auth.users
SET email_confirmed_at = NOW()
WHERE email = 'your@email.com' AND email_confirmed_at IS NULL;

-- 检查 m2_users
SELECT * FROM m2_users WHERE id = '<user_id>';
```

### 问题 4: 用户名冲突
```sql
-- 检查重复的用户名
SELECT username, COUNT(*) 
FROM m2_users 
GROUP BY username 
HAVING COUNT(*) > 1;

-- 查看所有用户名
SELECT username FROM m2_users ORDER BY username;
```

---

## 📊 监控建议

### 定期检查统计
```sql
-- 每周运行一次
SELECT * FROM fn_get_unverified_users_stats();
```

### 定期清理（可选）
```sql
-- 每月清理 30 天以上未验证的用户
SELECT * FROM fn_cleanup_unverified_users(30);
```

### 数据质量监控
```sql
-- 检查用户名格式异常
SELECT username FROM m2_users 
WHERE username !~ '^[a-zA-Z0-9_]+$' 
   OR LENGTH(username) < 3 
   OR LENGTH(username) > 30;

-- 检查孤立记录
SELECT COUNT(*) FROM m2_users mu
WHERE NOT EXISTS (SELECT 1 FROM auth.users au WHERE au.id = mu.id);
```

---

## 📝 回滚计划

如果需要回滚到 v3.0：

```sql
-- 1. 删除新触发器
DROP TRIGGER IF EXISTS trg_auth_users_create_profile ON auth.users;

-- 2. 恢复旧的触发器
CREATE OR REPLACE FUNCTION fn_create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO m2_users (id, username, display_name, avatar_url)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'username', NEW.email), 
            NEW.raw_user_meta_data->>'display_name', 
            NEW.raw_user_meta_data->>'avatar_url')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO m2_user_profiles (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auth_users_create_profile
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION fn_create_user_profile();
```

---

## 🎯 总结

完成以上步骤后，您将拥有：
- ✅ 无冗余数据的用户系统
- ✅ 完善的用户名注册功能
- ✅ 实时用户名可用性检查
- ✅ 数据清理和维护工具
- ✅ 更好的用户体验

预期效果：
- 数据库更干净，只存储真实激活用户
- 防止恶意用户名抢占
- 用户可以自定义喜欢的用户名
- 统计数据更准确

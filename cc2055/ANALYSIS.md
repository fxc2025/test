# 注册系统业务逻辑分析报告

## 问题 1: m2_users 自动创建时机分析

### 当前实现

**位置**: `cc2055/travel-supabase-schema-v3.sql` 第 950-969 行

```sql
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

**触发时机**: 用户在 `auth.users` 表中创建记录时立即触发，**不管邮箱是否验证**。

### 存在的问题

#### 1. 冗余数据问题 ⚠️
- **未验证用户占用资源**: 注册后从未验证邮箱的用户会产生无效的 `m2_users` 和 `m2_user_profiles` 记录
- **垃圾数据累积**: 恶意注册、测试账号、一次性邮箱等会持续占用数据库空间
- **统计数据失真**: 用户总数包含大量未激活账号，影响运营数据准确性

#### 2. 数据一致性问题 ⚠️
- **业务逻辑混乱**: 未验证用户也拥有完整的用户档案，但无法登录使用
- **关联数据孤立**: 如果后续添加基于邮箱验证的业务逻辑，需要额外过滤
- **用户体验矛盾**: 用户档案已存在但账号未激活

#### 3. 安全风险 ⚠️
- **用户名抢占**: 恶意用户可以批量注册占用热门用户名
- **资源浪费**: 每个未验证用户占用数据库空间、索引空间、统计计算资源

### 改进方案

#### 方案 A: 邮箱验证后创建 (推荐) ✅

**实现方式**:
1. 修改触发器监听 `email_confirmed_at` 字段变化
2. 只在邮箱验证成功时创建 `m2_users` 记录

**优点**:
- ✅ 数据干净，只有真实激活用户
- ✅ 避免垃圾数据累积
- ✅ 统计数据更准确
- ✅ 防止恶意抢占用户名

**缺点**:
- ❌ 需要修改触发器逻辑
- ❌ 需要处理已存在的未验证用户

**SQL 实现**:
```sql
-- 方案 A: 邮箱验证后创建
CREATE OR REPLACE FUNCTION fn_create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    -- 只在邮箱已验证时创建记录
    IF NEW.email_confirmed_at IS NOT NULL AND OLD.email_confirmed_at IS NULL THEN
        INSERT INTO m2_users (id, username, display_name, avatar_url)
        VALUES (
            NEW.id, 
            COALESCE(NEW.raw_user_meta_data->>'username', NEW.email), 
            NEW.raw_user_meta_data->>'display_name', 
            NEW.raw_user_meta_data->>'avatar_url'
        )
        ON CONFLICT (id) DO NOTHING;

        INSERT INTO m2_user_profiles (user_id)
        VALUES (NEW.id)
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 修改触发器为 AFTER UPDATE
DROP TRIGGER IF EXISTS trg_auth_users_create_profile ON auth.users;
CREATE TRIGGER trg_auth_users_create_profile
    AFTER INSERT OR UPDATE OF email_confirmed_at ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION fn_create_user_profile();
```

#### 方案 B: 首次登录时创建 ✅

**实现方式**:
在用户首次登录成功后，通过应用层代码检查并创建 `m2_users` 记录

**优点**:
- ✅ 确保只为真实使用用户创建记录
- ✅ 灵活性更高，可以收集更多用户信息
- ✅ 不依赖数据库触发器

**缺点**:
- ❌ 需要在多处登录逻辑中添加检查
- ❌ 应用层代码复杂度增加
- ❌ 可能出现竞态条件

#### 方案 C: 保持现状 + 定期清理 ⚡

**实现方式**:
保持当前自动创建逻辑，但添加定期清理机制

**优点**:
- ✅ 不需要修改现有触发器
- ✅ 实现简单

**缺点**:
- ❌ 仍会产生临时冗余数据
- ❌ 需要额外的定时任务
- ❌ 未解决用户名抢占问题

**SQL 实现**:
```sql
-- 定期清理 30 天未验证的用户
CREATE OR REPLACE FUNCTION fn_cleanup_unverified_users()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM m2_users
    WHERE id IN (
        SELECT u.id 
        FROM auth.users u
        WHERE u.email_confirmed_at IS NULL
          AND u.created_at < NOW() - INTERVAL '30 days'
    );
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- 使用 pg_cron 定期执行（每天凌晨 2 点）
-- SELECT cron.schedule('cleanup_unverified_users', '0 2 * * *', 
--     'SELECT fn_cleanup_unverified_users();');
```

---

## 问题 2: 邮箱和用户名重复检查

### 邮箱重复检查 ✅ 已实现

**检查位置**: Supabase Auth 系统自动处理

**实现机制**:
1. `auth.users` 表的 `email` 字段有**唯一约束**
2. 在 `src/app/api/auth/register/route.ts` 第 21 行调用 `supabaseAdmin.auth.admin.createUser()` 时自动检查
3. 如果邮箱已存在，Supabase 会返回错误: `"User already registered"`

**代码位置**:
```typescript
// src/app/api/auth/register/route.ts
const { data: authData, error: signUpError } = await supabaseAdmin.auth.admin.createUser({
  email,  // Supabase 自动检查邮箱唯一性
  password,
  email_confirm: false,
  user_metadata: { role },
})

if (signUpError) {
  // 邮箱重复时会返回错误
  return NextResponse.json<ApiResponse>(
    { success: false, error: signUpError.message },
    { status: 400 }
  )
}
```

### 用户名重复检查 ⚠️ 部分实现

**数据库约束**: `cc2055/travel-supabase-schema-v3.sql` 第 254 行

```sql
CREATE TABLE IF NOT EXISTS m2_users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username CITEXT NOT NULL UNIQUE,  -- 数据库层面有唯一约束
    -- ...
    CONSTRAINT username_length CHECK (char_length(username) BETWEEN 3 AND 30)
);
```

**问题分析**:

#### 1. 注册流程缺少 username 输入 ❌
- `src/app/(auth)/register/page.tsx` 没有 username 输入框
- 用户只能输入 email、password、role
- 无法自定义用户名

#### 2. API 不接收 username 参数 ❌
- `src/app/api/auth/register/route.ts` 只接收 `email`, `password`, `role`
- 没有 username 相关验证逻辑

#### 3. 自动生成用户名存在问题 ⚠️
- 当前触发器函数使用 `COALESCE(NEW.raw_user_meta_data->>'username', NEW.email)` 作为 username
- 如果未传入 username，直接使用 email 作为用户名
- 两个不同邮箱用户不会冲突，但用户体验差（用户名是邮箱格式）

#### 4. 没有前端重复检查 ❌
- 用户在注册时无法知道用户名是否已被占用
- 只能等到提交后收到数据库错误

### 改进方案

#### 方案 1: 添加用户名注册功能 (推荐) ✅

**Step 1: 修改注册表单** - 添加 username 输入框

```tsx
// src/app/(auth)/register/page.tsx
const [formData, setFormData] = useState<RegisterFormData>({
  email: '',
  username: '',  // 新增
  password: '',
  confirmPassword: '',
  role: 'user',
})

// 表单中添加
<div className="space-y-2">
  <Label htmlFor="username">用户名</Label>
  <Input
    id="username"
    name="username"
    type="text"
    placeholder="3-30个字符"
    value={formData.username}
    onChange={handleChange}
    required
    minLength={3}
    maxLength={30}
  />
</div>
```

**Step 2: 添加 API 用户名重复检查**

```typescript
// src/app/api/auth/register/route.ts
export async function POST(request: NextRequest) {
  const { email, username, password, role = 'user' } = await request.json()

  if (!email || !username || !password) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: '邮箱、用户名和密码不能为空' },
      { status: 400 }
    )
  }

  // 检查用户名格式
  if (username.length < 3 || username.length > 30) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: '用户名长度必须在 3-30 个字符之间' },
      { status: 400 }
    )
  }

  // 检查用户名是否已存在
  const { data: existingUser } = await supabaseAdmin
    .from('m2_users')
    .select('username')
    .eq('username', username.toLowerCase())
    .single()

  if (existingUser) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: '用户名已被占用' },
      { status: 400 }
    )
  }

  // 创建用户时传入 username
  const { data: authData, error: signUpError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: false,
    user_metadata: {
      role,
      username,  // 传入用户名
    },
  })

  // ... 其他逻辑
}
```

**Step 3: 更新类型定义**

```typescript
// src/types/index.ts
export interface RegisterFormData {
  email: string
  username: string  // 新增
  password: string
  confirmPassword: string
  role: 'user' | 'author'
}
```

#### 方案 2: 实时用户名可用性检查 ✨

添加 API 端点用于检查用户名是否可用：

```typescript
// src/app/api/auth/check-username/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const username = searchParams.get('username')

  if (!username) {
    return NextResponse.json({ available: false, error: '用户名不能为空' })
  }

  if (username.length < 3 || username.length > 30) {
    return NextResponse.json({ available: false, error: '用户名长度必须在 3-30 个字符之间' })
  }

  const { data } = await supabaseAdmin
    .from('m2_users')
    .select('username')
    .eq('username', username.toLowerCase())
    .single()

  return NextResponse.json({ 
    available: !data,
    message: data ? '用户名已被占用' : '用户名可用'
  })
}
```

前端添加防抖检查：

```tsx
// 在注册表单中添加
const [usernameAvailable, setUsernameAvailable] = useState<boolean | null>(null)
const [checkingUsername, setCheckingUsername] = useState(false)

const checkUsername = useMemo(
  () =>
    debounce(async (username: string) => {
      if (username.length < 3) return
      
      setCheckingUsername(true)
      const response = await fetch(`/api/auth/check-username?username=${username}`)
      const data = await response.json()
      setUsernameAvailable(data.available)
      setCheckingUsername(false)
    }, 500),
  []
)

const handleUsernameChange = (e: React.ChangeEvent<HTMLInputElement>) => {
  const username = e.target.value
  setFormData({ ...formData, username })
  checkUsername(username)
}
```

---

## 综合建议

### 优先级 P0 (必须修改)
1. ✅ **添加用户名注册功能** - 完善用户注册体验
2. ✅ **邮箱验证后创建 m2_users** - 避免冗余数据累积

### 优先级 P1 (强烈推荐)
3. ✅ **实时用户名可用性检查** - 提升用户体验
4. ✅ **清理现有未验证用户** - 清理历史数据

### 优先级 P2 (可选优化)
5. ⚡ **添加用户名规则验证** - 防止特殊字符、敏感词
6. ⚡ **用户名忽略大小写** - 使用 CITEXT 类型（已实现）

---

## 实施步骤

### Step 1: 修改数据库触发器
执行改进的 SQL 脚本，修改 `fn_create_user_profile()` 函数为邮箱验证后创建

### Step 2: 更新前端注册表单
添加 username 输入框，实现格式验证和可用性检查

### Step 3: 更新注册 API
添加 username 参数处理和重复检查逻辑

### Step 4: 更新类型定义
在 TypeScript 类型中添加 username 字段

### Step 5: 数据迁移
处理现有未验证用户，决定是否清理或保留

### Step 6: 测试验证
- 测试用户名重复注册
- 测试邮箱重复注册
- 测试邮箱验证流程
- 测试未验证用户是否创建 m2_users

---

## 总结

**当前状态**:
- ✅ 邮箱重复检查: 已由 Supabase Auth 自动处理
- ⚠️ 用户名重复检查: 仅数据库约束，缺少前端输入和验证
- ❌ m2_users 创建时机: 注册时立即创建，存在冗余数据风险

**推荐改进**:
1. 修改触发器为**邮箱验证后创建** m2_users 记录
2. 添加**用户名注册功能**，包含前端输入、API 验证、实时检查
3. 清理现有未验证用户数据

**预期效果**:
- 消除垃圾数据累积问题
- 提升用户注册体验
- 防止恶意用户名抢占
- 数据统计更准确可靠

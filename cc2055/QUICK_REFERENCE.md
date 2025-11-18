# 快速参考指南

## 问题 1: m2_users 自动创建时机

### ❌ 当前问题
```
用户注册 → 立即创建 m2_users → 未验证邮箱 → 产生冗余数据
```

### ✅ 改进方案
```
用户注册 → 发送验证邮件 → 验证邮箱 ✓ → 创建 m2_users
```

### 实施方法
1. 执行 SQL: `cc2055/travel-supabase-schema-v3-improved.sql`
2. 触发器从监听 `INSERT` 改为监听 `INSERT OR UPDATE OF email_confirmed_at`
3. 只在 `email_confirmed_at` 从 NULL 变为有值时创建记录

---

## 问题 2: 邮箱和用户名重复检查

### 邮箱重复检查 ✅ 已实现
- **位置**: Supabase Auth 自动处理
- **机制**: `auth.users.email` 有唯一约束
- **代码**: `supabaseAdmin.auth.admin.createUser()` 自动检查

### 用户名重复检查 ⚠️ 需要改进

#### 当前状态
```
❌ 无用户名输入框
❌ 无 API 检查
❌ 自动使用邮箱作为用户名
✅ 数据库有唯一约束 (m2_users.username)
```

#### 改进方案
```
✅ 添加用户名输入框
✅ 实时检查 API (/api/auth/check-username)
✅ 注册 API 支持 username 参数
✅ 格式验证 + 重复检查
```

---

## 核心改进代码

### 1. 数据库触发器（改进版）

```sql
CREATE OR REPLACE FUNCTION fn_create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    -- 只在邮箱验证时创建
    IF TG_OP = 'INSERT' AND NEW.email_confirmed_at IS NOT NULL THEN
        NULL;
    ELSIF TG_OP = 'UPDATE' AND OLD.email_confirmed_at IS NULL 
          AND NEW.email_confirmed_at IS NOT NULL THEN
        NULL;
    ELSE
        RETURN NEW;
    END IF;

    -- 插入 m2_users
    INSERT INTO m2_users (id, username, ...)
    VALUES (NEW.id, ...) 
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auth_users_create_profile
    AFTER INSERT OR UPDATE OF email_confirmed_at ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION fn_create_user_profile();
```

### 2. 用户名检查 API

```typescript
// src/app/api/auth/check-username/route.ts
export async function GET(request: NextRequest) {
  const username = searchParams.get('username')
  
  const { data } = await supabaseAdmin
    .from('m2_users')
    .select('username')
    .ilike('username', username)
    .single()

  return NextResponse.json({
    success: true,
    data: {
      available: !data,
      message: data ? '用户名已被占用' : '用户名可用'
    }
  })
}
```

### 3. 注册表单（前端）

```tsx
// 添加用户名输入框
<Input
  name="username"
  placeholder="3-30个字符"
  value={formData.username}
  onChange={handleChange}
/>

// 实时检查
useEffect(() => {
  const timeout = setTimeout(async () => {
    const response = await fetch(
      `/api/auth/check-username?username=${formData.username}`
    )
    const data = await response.json()
    setUsernameStatus(data.data)
  }, 500)
  
  return () => clearTimeout(timeout)
}, [formData.username])
```

---

## 常用 SQL 命令

### 查看统计
```sql
-- 未验证用户统计
SELECT * FROM fn_get_unverified_users_stats();
```

### 清理数据
```sql
-- 删除未验证用户的 m2_users（保留 auth.users）
SELECT fn_remove_m2_users_for_unverified();

-- 删除 30 天以上未验证的用户
SELECT * FROM fn_cleanup_unverified_users(30);
```

### 检查用户名
```sql
-- 检查用户名是否可用
SELECT fn_check_username_available('testuser');

-- 为邮箱生成唯一用户名
SELECT fn_generate_unique_username('test@example.com');
```

### 测试触发器
```sql
-- 1. 创建未验证用户
INSERT INTO auth.users (..., email_confirmed_at = NULL);

-- 2. 检查 m2_users（应该没有）
SELECT * FROM m2_users WHERE id = '<user_id>';

-- 3. 验证邮箱
UPDATE auth.users SET email_confirmed_at = NOW() WHERE id = '<user_id>';

-- 4. 再次检查 m2_users（应该有了）
SELECT * FROM m2_users WHERE id = '<user_id>';
```

---

## 测试清单

### 数据库
- [ ] 触发器正确更新为监听 email_confirmed_at
- [ ] 未验证用户不创建 m2_users
- [ ] 验证后自动创建 m2_users
- [ ] 用户名冲突自动处理

### API
- [ ] /api/auth/check-username 返回正确
- [ ] /api/auth/register 接收 username 参数
- [ ] 用户名格式验证生效
- [ ] 重复用户名被拒绝

### 前端
- [ ] 用户名输入框显示
- [ ] 实时检查（防抖 500ms）
- [ ] 可用/不可用提示显示
- [ ] 可选留空功能正常

### 集成
- [ ] 完整注册流程正常
- [ ] 不验证邮箱无 m2_users
- [ ] 验证后有 m2_users
- [ ] 用户名正确保存

---

## 关键点总结

### 为什么改进？
1. **数据质量**: 消除未验证用户的冗余数据
2. **安全性**: 防止恶意用户名抢占
3. **用户体验**: 支持自定义用户名 + 实时检查
4. **可维护性**: 统计更准确，数据更干净

### 主要变化
| 方面 | 之前 | 之后 |
|------|------|------|
| m2_users 创建 | 注册时 | 验证后 |
| 用户名输入 | 无 | 有 |
| 实时检查 | 无 | 有 |
| 数据清理 | 无 | 有 |

### 优先级
1. **P0 必须**: 修改触发器 + 添加用户名功能
2. **P1 推荐**: 实时检查 + 数据清理
3. **P2 可选**: 定时任务 + 监控

---

## 文档导航

- 📊 **详细分析**: [ANALYSIS.md](./ANALYSIS.md) - 问题深度分析
- 📖 **实施指南**: [IMPLEMENTATION_GUIDE.md](./IMPLEMENTATION_GUIDE.md) - 分步骤实施
- 💾 **改进脚本**: [travel-supabase-schema-v3-improved.sql](./travel-supabase-schema-v3-improved.sql)
- 📝 **总览**: [README.md](./README.md) - 项目概述

---

## 一行总结

**改进前**: 注册即创建，未验证也有记录，用户名是邮箱  
**改进后**: 验证后创建，数据干净，支持自定义用户名 ✅

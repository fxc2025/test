-- =====================================================
-- 旅行轨迹记录平台 - Supabase 数据库脚本 (v3.1 改进版)
-- Travel Tracker Database Schema for Supabase (v3.1)
-- =====================================================
-- 版本: v3.1 (改进版)
-- 创建时间: 2025-01-XX
-- 改进内容:
--   1. 修改 m2_users 创建时机为邮箱验证后
--   2. 添加用户名唯一性检查增强
--   3. 添加未验证用户清理函数
-- =====================================================

-- 注意：本文件只包含相对于 v3.0 的改进部分
-- 完整的表结构和其他内容请参考 travel-supabase-schema-v3.sql

-- -----------------------------------------------------
-- 改进 1: 邮箱验证后创建 m2_users 记录
-- -----------------------------------------------------

-- 删除旧的触发器和函数
DROP TRIGGER IF EXISTS trg_auth_users_create_profile ON auth.users;
DROP FUNCTION IF EXISTS fn_create_user_profile();

-- 创建改进的用户档案创建函数
CREATE OR REPLACE FUNCTION fn_create_user_profile()
RETURNS TRIGGER AS $$
DECLARE
    v_username CITEXT;
BEGIN
    -- 方案 A: 只在邮箱验证时创建记录
    -- 检查是否从未验证变为已验证
    IF TG_OP = 'INSERT' AND NEW.email_confirmed_at IS NOT NULL THEN
        -- 新用户且已验证（例如通过 admin.createUser 时 email_confirm: true）
        NULL; -- 继续执行下面的插入逻辑
    ELSIF TG_OP = 'UPDATE' AND OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
        -- 用户从未验证变为已验证
        NULL; -- 继续执行下面的插入逻辑
    ELSE
        -- 其他情况不创建记录
        RETURN NEW;
    END IF;

    -- 生成用户名：优先使用 metadata 中的 username，否则使用 email 的本地部分
    v_username := COALESCE(
        NEW.raw_user_meta_data->>'username',
        SPLIT_PART(NEW.email, '@', 1)
    );

    -- 处理用户名冲突：如果已存在，添加随机后缀
    WHILE EXISTS (SELECT 1 FROM m2_users WHERE username = v_username) LOOP
        v_username := COALESCE(
            NEW.raw_user_meta_data->>'username',
            SPLIT_PART(NEW.email, '@', 1)
        ) || '_' || SUBSTRING(MD5(RANDOM()::TEXT), 1, 6);
    END LOOP;

    -- 插入 m2_users 记录
    INSERT INTO m2_users (id, username, display_name, avatar_url, role)
    VALUES (
        NEW.id,
        v_username,
        NEW.raw_user_meta_data->>'display_name',
        NEW.raw_user_meta_data->>'avatar_url',
        COALESCE((NEW.raw_user_meta_data->>'role')::m2_user_role, 'user')
    )
    ON CONFLICT (id) DO NOTHING;

    -- 插入 m2_user_profiles 记录
    INSERT INTO m2_user_profiles (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;

    -- 初始化用户统计
    INSERT INTO m2_user_travel_stats (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION fn_create_user_profile() IS '邮箱验证后自动创建用户档案，避免未验证用户产生冗余数据';

-- 创建新的触发器：监听 INSERT 和 email_confirmed_at 的 UPDATE
CREATE TRIGGER trg_auth_users_create_profile
    AFTER INSERT OR UPDATE OF email_confirmed_at ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION fn_create_user_profile();

COMMENT ON TRIGGER trg_auth_users_create_profile ON auth.users IS '用户邮箱验证后自动创建 m2_users 和 m2_user_profiles';

-- -----------------------------------------------------
-- 改进 2: 用户名检查辅助函数
-- -----------------------------------------------------

-- 检查用户名是否可用
CREATE OR REPLACE FUNCTION fn_check_username_available(p_username CITEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1 FROM m2_users WHERE username = p_username
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION fn_check_username_available(CITEXT) IS '检查用户名是否可用';

-- 生成唯一用户名（基于 email）
CREATE OR REPLACE FUNCTION fn_generate_unique_username(p_email TEXT)
RETURNS CITEXT AS $$
DECLARE
    v_base_username CITEXT;
    v_username CITEXT;
    v_counter INTEGER := 0;
BEGIN
    -- 提取 email 的本地部分作为基础用户名
    v_base_username := SPLIT_PART(p_email, '@', 1);
    v_username := v_base_username;

    -- 如果用户名已存在，添加数字后缀
    WHILE EXISTS (SELECT 1 FROM m2_users WHERE username = v_username) LOOP
        v_counter := v_counter + 1;
        v_username := v_base_username || v_counter::TEXT;
        
        -- 防止无限循环
        IF v_counter > 1000 THEN
            v_username := v_base_username || '_' || SUBSTRING(MD5(RANDOM()::TEXT), 1, 8);
            EXIT;
        END IF;
    END LOOP;

    RETURN v_username;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_generate_unique_username(TEXT) IS '基于邮箱生成唯一用户名';

-- -----------------------------------------------------
-- 改进 3: 未验证用户清理函数
-- -----------------------------------------------------

-- 清理指定天数未验证的用户
CREATE OR REPLACE FUNCTION fn_cleanup_unverified_users(p_days INTEGER DEFAULT 30)
RETURNS TABLE (
    deleted_count INTEGER,
    deleted_user_ids UUID[]
) AS $$
DECLARE
    v_deleted_ids UUID[];
    v_count INTEGER;
BEGIN
    -- 收集要删除的用户 ID
    SELECT ARRAY_AGG(u.id)
    INTO v_deleted_ids
    FROM auth.users u
    WHERE u.email_confirmed_at IS NULL
      AND u.created_at < NOW() - (p_days || ' days')::INTERVAL
      AND NOT EXISTS (
          SELECT 1 FROM m2_users mu WHERE mu.id = u.id
      );

    -- 删除这些用户（cascade 会自动删除 auth.users）
    DELETE FROM auth.users
    WHERE id = ANY(v_deleted_ids);

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN QUERY SELECT v_count, COALESCE(v_deleted_ids, ARRAY[]::UUID[]);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION fn_cleanup_unverified_users(INTEGER) IS '清理指定天数未验证的用户（默认30天）';

-- 清理孤立的 m2_users 记录（auth.users 已删除但 m2_users 还在）
CREATE OR REPLACE FUNCTION fn_cleanup_orphaned_m2_users()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM m2_users
    WHERE NOT EXISTS (
        SELECT 1 FROM auth.users au WHERE au.id = m2_users.id
    );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION fn_cleanup_orphaned_m2_users() IS '清理孤立的 m2_users 记录';

-- -----------------------------------------------------
-- 改进 4: 定时清理任务 (可选)
-- -----------------------------------------------------

-- 如果启用了 pg_cron 扩展，可以创建定时任务
-- 注意：Supabase 的 pg_cron 可能需要特殊权限，建议通过 Supabase Functions 或外部调度

-- 示例：每天凌晨 3 点清理 30 天未验证的用户
/*
SELECT cron.schedule(
    'cleanup_unverified_users_daily',
    '0 3 * * *',
    $$
    SELECT fn_cleanup_unverified_users(30);
    $$
);
*/

-- 示例：每周日凌晨 4 点清理孤立记录
/*
SELECT cron.schedule(
    'cleanup_orphaned_users_weekly',
    '0 4 * * 0',
    $$
    SELECT fn_cleanup_orphaned_m2_users();
    $$
);
*/

-- -----------------------------------------------------
-- 改进 5: 数据迁移（处理现有未验证用户）
-- -----------------------------------------------------

-- 查看当前未验证用户统计
CREATE OR REPLACE FUNCTION fn_get_unverified_users_stats()
RETURNS TABLE (
    total_unverified_users BIGINT,
    unverified_with_m2_users BIGINT,
    unverified_without_m2_users BIGINT,
    oldest_unverified_date TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE au.email_confirmed_at IS NULL) AS total_unverified_users,
        COUNT(*) FILTER (WHERE au.email_confirmed_at IS NULL AND mu.id IS NOT NULL) AS unverified_with_m2_users,
        COUNT(*) FILTER (WHERE au.email_confirmed_at IS NULL AND mu.id IS NULL) AS unverified_without_m2_users,
        MIN(au.created_at) FILTER (WHERE au.email_confirmed_at IS NULL) AS oldest_unverified_date
    FROM auth.users au
    LEFT JOIN m2_users mu ON mu.id = au.id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_get_unverified_users_stats() IS '获取未验证用户统计信息';

-- 手动清理所有未验证用户的 m2_users 记录（不删除 auth.users）
CREATE OR REPLACE FUNCTION fn_remove_m2_users_for_unverified()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM m2_users
    WHERE id IN (
        SELECT au.id
        FROM auth.users au
        WHERE au.email_confirmed_at IS NULL
    );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION fn_remove_m2_users_for_unverified() IS '删除所有未验证用户的 m2_users 记录';

-- -----------------------------------------------------
-- 使用说明
-- -----------------------------------------------------

/*
## 部署步骤

1. **备份数据库**
   ```sql
   -- 通过 Supabase Dashboard 或 pg_dump 备份
   ```

2. **执行改进脚本**
   ```sql
   -- 在 Supabase SQL Editor 中执行本文件
   ```

3. **查看未验证用户统计**
   ```sql
   SELECT * FROM fn_get_unverified_users_stats();
   ```

4. **可选：清理现有未验证用户的 m2_users 记录**
   ```sql
   SELECT fn_remove_m2_users_for_unverified();
   ```

5. **可选：删除长期未验证的用户**
   ```sql
   -- 清理 30 天以上未验证的用户
   SELECT * FROM fn_cleanup_unverified_users(30);
   ```

6. **测试验证**
   - 注册新用户（不验证邮箱）
   - 检查 m2_users 表，应该没有新记录
   - 验证邮箱
   - 检查 m2_users 表，应该有新记录

## 常用查询

-- 查看未验证用户数量
SELECT COUNT(*) FROM auth.users WHERE email_confirmed_at IS NULL;

-- 查看有 m2_users 记录但未验证邮箱的用户
SELECT au.email, au.created_at, mu.username
FROM auth.users au
INNER JOIN m2_users mu ON mu.id = au.id
WHERE au.email_confirmed_at IS NULL;

-- 查看所有用户的验证状态
SELECT 
    au.email,
    au.email_confirmed_at,
    mu.username,
    au.created_at
FROM auth.users au
LEFT JOIN m2_users mu ON mu.id = au.id
ORDER BY au.created_at DESC;

-- 手动验证用户（测试用）
UPDATE auth.users
SET email_confirmed_at = NOW()
WHERE email = 'test@example.com';

-- 检查用户名是否可用
SELECT fn_check_username_available('testuser');

-- 为邮箱生成唯一用户名
SELECT fn_generate_unique_username('test@example.com');
*/

-- -----------------------------------------------------
-- 脚本结束
-- -----------------------------------------------------

-- 提示信息
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Supabase Schema v3.1 改进脚本执行完成';
    RAISE NOTICE '========================================';
    RAISE NOTICE '主要改进:';
    RAISE NOTICE '1. ✅ m2_users 记录现在在邮箱验证后创建';
    RAISE NOTICE '2. ✅ 添加了用户名可用性检查函数';
    RAISE NOTICE '3. ✅ 添加了未验证用户清理函数';
    RAISE NOTICE '4. ✅ 添加了统计和迁移辅助函数';
    RAISE NOTICE '========================================';
    RAISE NOTICE '下一步操作:';
    RAISE NOTICE '1. 运行: SELECT * FROM fn_get_unverified_users_stats();';
    RAISE NOTICE '2. 考虑是否清理现有未验证用户';
    RAISE NOTICE '3. 更新前端注册表单添加 username 字段';
    RAISE NOTICE '4. 更新注册 API 添加用户名检查';
    RAISE NOTICE '========================================';
END $$;

-- =====================================================
-- 旅行轨迹记录平台 - Supabase 数据库脚本 (v3.0 优化版)
-- Travel Tracker Database Schema for Supabase (v3)
-- =====================================================
-- 版本: v3.0
-- 创建时间: 2025-11-18
-- 目标平台: Supabase (PostgreSQL 15 + PostGIS)
-- 前缀规范: 所有业务表使用 m2_ 前缀
-- 说明:
--   1. 本脚本遵循 Supabase 最佳实践，默认位于 public schema
--   2. 依赖 PostGIS、pgcrypto、pg_trgm 等扩展
--   3. 全量定义触发器、RLS 策略、默认数据
-- =====================================================

-- -----------------------------------------------------
-- 0. 基础设置
-- -----------------------------------------------------
SET search_path = public;
SET timezone = 'Asia/Shanghai';

-- -----------------------------------------------------
-- 1. 必要扩展
-- -----------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- 提供 gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "postgis";        -- 地理信息处理
CREATE EXTENSION IF NOT EXISTS "postgis_topology";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";        -- 模糊查询
CREATE EXTENSION IF NOT EXISTS "citext";        -- 不区分大小写文本

-- -----------------------------------------------------
-- 2. 公共类型与函数
-- -----------------------------------------------------

-- 用户角色枚举
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'm2_user_role') THEN
        CREATE TYPE m2_user_role AS ENUM ('user', 'author', 'admin');
    END IF;
END $$;

-- 支付状态枚举
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'm2_payment_status') THEN
        CREATE TYPE m2_payment_status AS ENUM ('pending', 'paid', 'refunded', 'closed');
    END IF;
END $$;

-- 通知类型枚举
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'm2_notification_type') THEN
        CREATE TYPE m2_notification_type AS ENUM (
            'system',
            'comment',
            'like',
            'follow',
            'sponsorship',
            'message',
            'article'
        );
    END IF;
END $$;

-- 通知状态枚举
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'm2_notification_status') THEN
        CREATE TYPE m2_notification_status AS ENUM ('unread', 'read');
    END IF;
END $$;

-- 内容状态常量: 0 草稿, 1 已发布, 2 已删除
-- 使用 smallint + CHECK 约束，便于跨语言处理

-- 内容目标类型常量: 1 文章, 2 时光轴, 3 评论, 4 照片

-- 更新时间触发器函数
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 轨迹点同步函数 (文章/时光轴/照片)
CREATE OR REPLACE FUNCTION fn_sync_track_point()
RETURNS TRIGGER AS $$
DECLARE
    v_point_type SMALLINT;
    v_related_id UUID;
    v_location GEOGRAPHY(Point, 4326);
    v_address VARCHAR;
    v_city VARCHAR;
    v_title TEXT;
    v_icon VARCHAR;
    v_color VARCHAR;
    v_show BOOLEAN;
    v_point_time TIMESTAMPTZ;
BEGIN
    IF TG_TABLE_NAME = 'm2_articles' THEN
        v_point_type := 1;
        v_related_id := COALESCE(NEW.id, OLD.id);
        v_location := NEW.location;
        v_address := NEW.address;
        v_city := NEW.city;
        v_title := NEW.title;
        v_show := COALESCE(NEW.show_on_track, FALSE);
        v_point_time := COALESCE(NEW.published_at, NEW.created_at);
        v_icon := 'article';
        v_color := '#E74C3C';
    ELSIF TG_TABLE_NAME = 'm2_timeline_posts' THEN
        v_point_type := 2;
        v_related_id := COALESCE(NEW.id, OLD.id);
        v_location := NEW.location;
        v_address := NEW.address;
        v_city := NULL;
        v_title := LEFT(NEW.content, 60);
        v_show := COALESCE(NEW.show_on_track, FALSE);
        v_point_time := NEW.created_at;
        v_icon := 'timeline';
        v_color := '#3498DB';
    ELSIF TG_TABLE_NAME = 'm2_photos' THEN
        v_point_type := 3;
        v_related_id := COALESCE(NEW.id, OLD.id);
        v_location := NEW.location;
        v_address := NEW.address;
        v_city := NULL;
        v_title := COALESCE(NEW.description, '旅途照片');
        v_show := COALESCE(NEW.show_on_track, FALSE);
        v_point_time := COALESCE(NEW.shoot_date, NEW.created_at);
        v_icon := 'photo';
        v_color := '#2ECC71';
    ELSE
        RETURN NULL;
    END IF;

    IF TG_OP = 'DELETE' OR v_show = FALSE OR v_location IS NULL THEN
        DELETE FROM m2_track_points
        WHERE point_type = v_point_type
          AND related_id = v_related_id;
        RETURN NEW;
    END IF;

    INSERT INTO m2_track_points AS tp (
        user_id,
        location,
        address,
        city,
        point_type,
        related_id,
        title,
        description,
        icon,
        color,
        point_time,
        is_public
    ) VALUES (
        NEW.user_id,
        v_location,
        v_address,
        v_city,
        v_point_type,
        v_related_id,
        v_title,
        NULL,
        v_icon,
        v_color,
        v_point_time,
        TRUE
    )
    ON CONFLICT (point_type, related_id)
    DO UPDATE SET
        user_id   = EXCLUDED.user_id,
        location  = EXCLUDED.location,
        address   = EXCLUDED.address,
        city      = EXCLUDED.city,
        title     = EXCLUDED.title,
        icon      = EXCLUDED.icon,
        color     = EXCLUDED.color,
        point_time= EXCLUDED.point_time,
        is_public = EXCLUDED.is_public;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 用户统计刷新函数
CREATE OR REPLACE FUNCTION fn_refresh_user_travel_stats(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO m2_user_travel_stats (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    UPDATE m2_user_travel_stats uts
    SET
        total_distance = COALESCE(stats.total_distance, 0),
        total_days = COALESCE(stats.total_days, 0),
        cities_count = COALESCE(stats.cities_count, 0),
        articles_count = COALESCE(stats.articles_count, 0),
        timeline_posts_count = COALESCE(stats.timeline_posts_count, 0),
        photos_count = COALESCE(stats.photos_count, 0),
        total_likes_received = COALESCE(stats.total_likes_received, 0),
        total_comments_received = COALESCE(stats.total_comments_received, 0),
        followers_count = COALESCE(stats.followers_count, 0),
        last_updated = NOW()
    FROM (
        SELECT
            u.id AS user_id,
            SUM(COALESCE(a.travel_distance, 0)) AS total_distance,
            CASE
                WHEN MIN(a.travel_date) IS NULL OR MAX(a.travel_date) IS NULL THEN 0
                ELSE (MAX(a.travel_date) - MIN(a.travel_date)) + 1
            END AS total_days,
            COUNT(DISTINCT NULLIF(a.city, '')) + COUNT(DISTINCT NULLIF(tp.city, '')) AS cities_count,
            COUNT(DISTINCT a.id) AS articles_count,
            COUNT(DISTINCT tl.id) AS timeline_posts_count,
            COUNT(DISTINCT ph.id) AS photos_count,
            SUM(COALESCE(a.like_count, 0)) + SUM(COALESCE(tl.like_count, 0)) + SUM(COALESCE(ph.like_count, 0)) AS total_likes_received,
            SUM(COALESCE(a.comment_count, 0)) + SUM(COALESCE(tl.comment_count, 0)) + SUM(COALESCE(ph.comment_count, 0)) AS total_comments_received,
            (SELECT COUNT(*) FROM m2_user_follows uf WHERE uf.following_id = u.id) AS followers_count
        FROM m2_users u
        LEFT JOIN m2_articles a ON a.user_id = u.id AND a.status = 1
        LEFT JOIN m2_timeline_posts tl ON tl.user_id = u.id AND tl.status = 1
        LEFT JOIN m2_photos ph ON ph.user_id = u.id AND ph.status = 1
        LEFT JOIN m2_track_points tp ON tp.user_id = u.id AND tp.is_public = TRUE
        WHERE u.id = p_user_id
        GROUP BY u.id
    ) stats
    WHERE uts.user_id = stats.user_id;
END;
$$ LANGUAGE plpgsql;

-- 自动刷新统计的通用触发器
CREATE OR REPLACE FUNCTION fn_trigger_refresh_user_stats()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM fn_refresh_user_travel_stats(COALESCE(NEW.user_id, OLD.user_id));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------
-- 3. 用户系统
-- -----------------------------------------------------

-- 用户基础表（扩展自 auth.users）
CREATE TABLE IF NOT EXISTS m2_users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username CITEXT NOT NULL UNIQUE,
    display_name VARCHAR(80),
    avatar_url VARCHAR(500),
    role m2_user_role NOT NULL DEFAULT 'user',
    is_author BOOLEAN NOT NULL DEFAULT FALSE,
    status SMALLINT NOT NULL DEFAULT 1 CHECK (status IN (0, 1, 2)),
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT username_length CHECK (char_length(username) BETWEEN 3 AND 30)
);

CREATE TRIGGER trg_m2_users_updated
    BEFORE UPDATE ON m2_users
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE m2_users IS '用户基础信息，与 auth.users 对齐';

-- 用户扩展资料
CREATE TABLE IF NOT EXISTS m2_user_profiles (
    user_id UUID PRIMARY KEY REFERENCES m2_users(id) ON DELETE CASCADE,
    bio TEXT,
    headline VARCHAR(120),
    location VARCHAR(120),
    website_url VARCHAR(200),
    social_links JSONB DEFAULT '{}'::jsonb,
    preferences JSONB DEFAULT '{}'::jsonb,
    language VARCHAR(10) DEFAULT 'zh-CN',
    time_zone VARCHAR(50) DEFAULT 'Asia/Shanghai',
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_m2_user_profiles_updated
    BEFORE UPDATE ON m2_user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- 用户统计表
CREATE TABLE IF NOT EXISTS m2_user_travel_stats (
    user_id UUID PRIMARY KEY REFERENCES m2_users(id) ON DELETE CASCADE,
    total_distance NUMERIC(12, 2) DEFAULT 0,
    total_days INTEGER DEFAULT 0,
    cities_count INTEGER DEFAULT 0,
    articles_count INTEGER DEFAULT 0,
    timeline_posts_count INTEGER DEFAULT 0,
    photos_count INTEGER DEFAULT 0,
    total_likes_received INTEGER DEFAULT 0,
    total_comments_received INTEGER DEFAULT 0,
    total_views INTEGER DEFAULT 0,
    followers_count INTEGER DEFAULT 0,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 用户关注关系
CREATE TABLE IF NOT EXISTS m2_user_follows (
    follower_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (follower_id, following_id),
    CONSTRAINT m2_user_follows_not_self CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_m2_user_follows_follower ON m2_user_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_m2_user_follows_following ON m2_user_follows(following_id);

-- -----------------------------------------------------
-- 4. 内容体系
-- -----------------------------------------------------

-- 文章分类
CREATE TABLE IF NOT EXISTS m2_article_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    display_order INTEGER DEFAULT 0,
    status SMALLINT NOT NULL DEFAULT 1 CHECK (status IN (0, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_m2_article_categories_updated
    BEFORE UPDATE ON m2_article_categories
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

INSERT INTO m2_article_categories (name, description, display_order)
VALUES
    ('旅行日记', '详细记录旅途见闻', 1),
    ('城市印象', '以城市为主题的游记', 2),
    ('自然风光', '自然景观与户外体验', 3),
    ('美食体验', '旅途中的美食推荐', 4)
ON CONFLICT (name) DO NOTHING;

-- 旅行文章
CREATE TABLE IF NOT EXISTS m2_articles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES m2_article_categories(id) ON DELETE SET NULL,
    title VARCHAR(200) NOT NULL,
    summary TEXT,
    content TEXT NOT NULL,
    cover_image VARCHAR(500),
    travel_date DATE NOT NULL,
    travel_method VARCHAR(50),
    travel_distance NUMERIC(10, 2),
    location GEOGRAPHY(Point, 4326),
    address VARCHAR(255),
    city VARCHAR(80),
    province VARCHAR(80),
    country VARCHAR(80) DEFAULT '中国',
    show_on_track BOOLEAN NOT NULL DEFAULT TRUE,
    tags TEXT[] DEFAULT '{}',
    mood_score SMALLINT CHECK (mood_score BETWEEN 1 AND 5),
    weather VARCHAR(50),
    temperature NUMERIC(5,2),
    recommendation_rating SMALLINT CHECK (recommendation_rating BETWEEN 1 AND 5),
    extension_fields JSONB DEFAULT '{}'::jsonb,
    view_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    bookmark_count INTEGER DEFAULT 0,
    status SMALLINT NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    CONSTRAINT m2_articles_title_not_empty CHECK (char_length(trim(title)) > 0),
    CONSTRAINT m2_articles_content_not_empty CHECK (char_length(trim(content)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_m2_articles_user_id ON m2_articles(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_articles_status ON m2_articles(status);
CREATE INDEX IF NOT EXISTS idx_m2_articles_published_at ON m2_articles(published_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_m2_articles_travel_date ON m2_articles(travel_date DESC);
CREATE INDEX IF NOT EXISTS idx_m2_articles_tags ON m2_articles USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_m2_articles_location ON m2_articles USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_m2_articles_search ON m2_articles
    USING GIN (to_tsvector('chinese', coalesce(title,'') || ' ' || coalesce(summary,'') || ' ' || coalesce(content,'')));

CREATE TRIGGER trg_m2_articles_updated
    BEFORE UPDATE ON m2_articles
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_m2_articles_track_point
    AFTER INSERT OR UPDATE OR DELETE ON m2_articles
    FOR EACH ROW
    EXECUTE FUNCTION fn_sync_track_point();

CREATE TRIGGER trg_m2_articles_refresh_stats
    AFTER INSERT OR UPDATE OR DELETE ON m2_articles
    FOR EACH ROW
    EXECUTE FUNCTION fn_trigger_refresh_user_stats();

-- 专题
CREATE TABLE IF NOT EXISTS m2_special_topics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    cover_image VARCHAR(500),
    tags TEXT[] DEFAULT '{}',
    article_count INTEGER DEFAULT 0,
    status SMALLINT NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_m2_special_topics_user_id ON m2_special_topics(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_special_topics_status ON m2_special_topics(status);
CREATE INDEX IF NOT EXISTS idx_m2_special_topics_tags ON m2_special_topics USING GIN(tags);

CREATE TRIGGER trg_m2_special_topics_updated
    BEFORE UPDATE ON m2_special_topics
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- 专题与文章关联
CREATE TABLE IF NOT EXISTS m2_topic_article_relations (
    topic_id UUID NOT NULL REFERENCES m2_special_topics(id) ON DELETE CASCADE,
    article_id UUID NOT NULL REFERENCES m2_articles(id) ON DELETE CASCADE,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (topic_id, article_id)
);

CREATE INDEX IF NOT EXISTS idx_m2_topic_article_relations_topic ON m2_topic_article_relations(topic_id, display_order);
CREATE INDEX IF NOT EXISTS idx_m2_topic_article_relations_article ON m2_topic_article_relations(article_id);

-- 时光轴
CREATE TABLE IF NOT EXISTS m2_timeline_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    content VARCHAR(500) NOT NULL,
    milestone VARCHAR(120),
    mood_tag VARCHAR(50),
    weather_tag VARCHAR(50),
    location GEOGRAPHY(Point, 4326),
    address VARCHAR(255),
    show_on_track BOOLEAN NOT NULL DEFAULT FALSE,
    images JSONB DEFAULT '[]'::jsonb,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    related_article_id UUID REFERENCES m2_articles(id) ON DELETE SET NULL,
    extension_fields JSONB DEFAULT '{}'::jsonb,
    status SMALLINT NOT NULL DEFAULT 1 CHECK (status IN (0, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_user_id ON m2_timeline_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_created_at ON m2_timeline_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_status ON m2_timeline_posts(status);
CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_location ON m2_timeline_posts USING GIST(location);

CREATE TRIGGER trg_m2_timeline_posts_updated
    BEFORE UPDATE ON m2_timeline_posts
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_m2_timeline_posts_track_point
    AFTER INSERT OR UPDATE OR DELETE ON m2_timeline_posts
    FOR EACH ROW
    EXECUTE FUNCTION fn_sync_track_point();

CREATE TRIGGER trg_m2_timeline_posts_refresh_stats
    AFTER INSERT OR UPDATE OR DELETE ON m2_timeline_posts
    FOR EACH ROW
    EXECUTE FUNCTION fn_trigger_refresh_user_stats();

-- 照片墙
CREATE TABLE IF NOT EXISTS m2_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    file_url VARCHAR(500) NOT NULL,
    thumbnail_url VARCHAR(500),
    width INTEGER,
    height INTEGER,
    size_bytes BIGINT,
    description VARCHAR(255),
    location GEOGRAPHY(Point, 4326),
    address VARCHAR(255),
    shoot_date TIMESTAMPTZ,
    show_on_track BOOLEAN NOT NULL DEFAULT FALSE,
    category VARCHAR(50) NOT NULL DEFAULT 'other',
    tags TEXT[] DEFAULT '{}',
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    status SMALLINT NOT NULL DEFAULT 1 CHECK (status IN (0, 1)),
    extension_fields JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_m2_photos_user_id ON m2_photos(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_photos_category ON m2_photos(category);
CREATE INDEX IF NOT EXISTS idx_m2_photos_tags ON m2_photos USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_m2_photos_location ON m2_photos USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_m2_photos_shoot_date ON m2_photos(shoot_date DESC);

CREATE TRIGGER trg_m2_photos_updated
    BEFORE UPDATE ON m2_photos
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_m2_photos_track_point
    AFTER INSERT OR UPDATE OR DELETE ON m2_photos
    FOR EACH ROW
    EXECUTE FUNCTION fn_sync_track_point();

CREATE TRIGGER trg_m2_photos_refresh_stats
    AFTER INSERT OR UPDATE OR DELETE ON m2_photos
    FOR EACH ROW
    EXECUTE FUNCTION fn_trigger_refresh_user_stats();

-- -----------------------------------------------------
-- 5. 轨迹系统
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS m2_track_points (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    address VARCHAR(255),
    city VARCHAR(80),
    point_type SMALLINT NOT NULL CHECK (point_type IN (1, 2, 3)),
    related_id UUID NOT NULL,
    title VARCHAR(200),
    description TEXT,
    icon VARCHAR(50),
    color VARCHAR(20),
    point_time TIMESTAMPTZ NOT NULL,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (point_type, related_id)
);

CREATE INDEX IF NOT EXISTS idx_m2_track_points_user_id ON m2_track_points(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_track_points_point_type ON m2_track_points(point_type);
CREATE INDEX IF NOT EXISTS idx_m2_track_points_location ON m2_track_points USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_m2_track_points_time ON m2_track_points(point_time DESC);

CREATE TABLE IF NOT EXISTS m2_track_segments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    start_point_id UUID NOT NULL REFERENCES m2_track_points(id) ON DELETE CASCADE,
    end_point_id UUID NOT NULL REFERENCES m2_track_points(id) ON DELETE CASCADE,
    travel_method VARCHAR(50),
    distance_km NUMERIC(10,2),
    duration_minutes INTEGER,
    path GEOGRAPHY(LineString, 4326),
    segment_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT m2_track_segments_points_different CHECK (start_point_id <> end_point_id)
);

CREATE INDEX IF NOT EXISTS idx_m2_track_segments_user ON m2_track_segments(user_id, segment_order);

-- -----------------------------------------------------
-- 6. 社交互动
-- -----------------------------------------------------

-- 评论
CREATE TABLE IF NOT EXISTS m2_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 4)), -- 评论的对象
    target_id UUID NOT NULL,
    parent_id UUID REFERENCES m2_comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    like_count INTEGER DEFAULT 0,
    status SMALLINT NOT NULL DEFAULT 1 CHECK (status IN (0, 1, 2)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_m2_comments_target ON m2_comments(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_m2_comments_parent ON m2_comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_m2_comments_user_id ON m2_comments(user_id);

CREATE TRIGGER trg_m2_comments_updated
    BEFORE UPDATE ON m2_comments
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_m2_comments_refresh_stats
    AFTER INSERT OR UPDATE OR DELETE ON m2_comments
    FOR EACH ROW
    EXECUTE FUNCTION fn_trigger_refresh_user_stats();

-- 点赞
CREATE TABLE IF NOT EXISTS m2_likes (
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 3, 4)),
    target_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_m2_likes_target ON m2_likes(target_type, target_id);

CREATE TRIGGER trg_m2_likes_refresh_stats
    AFTER INSERT OR DELETE ON m2_likes
    FOR EACH ROW
    EXECUTE FUNCTION fn_trigger_refresh_user_stats();

-- 收藏
CREATE TABLE IF NOT EXISTS m2_bookmarks (
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 4)),
    target_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_m2_bookmarks_target ON m2_bookmarks(target_type, target_id);

-- 分享
CREATE TABLE IF NOT EXISTS m2_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 4)),
    target_id UUID NOT NULL,
    platform VARCHAR(50),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_m2_shares_user ON m2_shares(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_shares_target ON m2_shares(target_type, target_id);

-- 浏览记录
CREATE TABLE IF NOT EXISTS m2_view_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES m2_users(id) ON DELETE SET NULL,
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 4)),
    target_id UUID NOT NULL,
    duration_seconds INTEGER,
    device VARCHAR(80),
    platform VARCHAR(20),
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- 最近 90 天分区示例
CREATE TABLE IF NOT EXISTS m2_view_logs_recent
    PARTITION OF m2_view_logs
    FOR VALUES FROM (NOW() - INTERVAL '90 days') TO (MAXVALUE);

-- -----------------------------------------------------
-- 7. 留言与赞助
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS m2_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES m2_users(id) ON DELETE SET NULL, -- 留言者
    author_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE, -- 作者
    content TEXT NOT NULL,
    reply_content TEXT,
    status SMALLINT NOT NULL DEFAULT 1 CHECK (status IN (0, 1, 2)),
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_m2_messages_author ON m2_messages(author_id);
CREATE INDEX IF NOT EXISTS idx_m2_messages_status ON m2_messages(status);

CREATE TRIGGER trg_m2_messages_updated
    BEFORE UPDATE ON m2_messages
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS m2_sponsorships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    message TEXT,
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
    payment_status m2_payment_status NOT NULL DEFAULT 'pending',
    payment_channel VARCHAR(50) DEFAULT 'wechat',
    transaction_no VARCHAR(100),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_m2_sponsorships_author ON m2_sponsorships(author_id);
CREATE INDEX IF NOT EXISTS idx_m2_sponsorships_user ON m2_sponsorships(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_sponsorships_status ON m2_sponsorships(payment_status);

-- -----------------------------------------------------
-- 8. 系统配置与通知
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS m2_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    type m2_notification_type NOT NULL,
    title VARCHAR(150),
    content TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    status m2_notification_status NOT NULL DEFAULT 'unread',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_m2_notifications_user ON m2_notifications(user_id, status);

CREATE TABLE IF NOT EXISTS m2_system_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    config_key VARCHAR(120) NOT NULL UNIQUE,
    config_value TEXT,
    config_type VARCHAR(50) DEFAULT 'text',
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_m2_system_configs_updated
    BEFORE UPDATE ON m2_system_configs
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- -----------------------------------------------------
-- 9. 视图与物化视图
-- -----------------------------------------------------

CREATE OR REPLACE VIEW v_article_public AS
SELECT
    a.id,
    a.title,
    a.summary,
    a.cover_image,
    a.travel_date,
    a.travel_method,
    a.travel_distance,
    a.address,
    a.city,
    a.country,
    a.tags,
    a.view_count,
    a.like_count,
    a.comment_count,
    a.share_count,
    a.bookmark_count,
    a.published_at,
    u.username,
    u.display_name,
    u.avatar_url
FROM m2_articles a
JOIN m2_users u ON u.id = a.user_id
WHERE a.status = 1;

COMMENT ON VIEW v_article_public IS '公开文章列表视图，包含作者信息';

-- -----------------------------------------------------
-- 10. 行级安全 (RLS)
-- -----------------------------------------------------

-- 启用 RLS
ALTER TABLE m2_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_user_travel_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_user_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_article_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_special_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_topic_article_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_timeline_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_track_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_track_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_sponsorships ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_system_configs ENABLE ROW LEVEL SECURITY;

-- m2_users: 所有人可读取公开用户，用户可更新自己
DROP POLICY IF EXISTS "Public users view" ON m2_users;
CREATE POLICY "Public users view"
    ON m2_users FOR SELECT
    USING (status = 1);

DROP POLICY IF EXISTS "Users manage self" ON m2_users;
CREATE POLICY "Users manage self"
    ON m2_users FOR UPDATE
    USING (auth.uid() = id);

-- m2_user_profiles: 公开读取，用户可更新自己
DROP POLICY IF EXISTS "Public profiles view" ON m2_user_profiles;
CREATE POLICY "Public profiles view"
    ON m2_user_profiles FOR SELECT
    USING (TRUE);

DROP POLICY IF EXISTS "Users manage own profile" ON m2_user_profiles;
CREATE POLICY "Users manage own profile"
    ON m2_user_profiles FOR ALL
    USING (auth.uid() = user_id);

-- m2_articles: 公共阅读，作者管理自己的文章
DROP POLICY IF EXISTS "Public articles view" ON m2_articles;
CREATE POLICY "Public articles view"
    ON m2_articles FOR SELECT
    USING (status = 1);

DROP POLICY IF EXISTS "Authors read own articles" ON m2_articles;
CREATE POLICY "Authors read own articles"
    ON m2_articles FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authors write own articles" ON m2_articles;
CREATE POLICY "Authors write own articles"
    ON m2_articles FOR ALL
    USING (auth.uid() = user_id);

-- m2_timeline_posts: 同上
DROP POLICY IF EXISTS "Public timeline view" ON m2_timeline_posts;
CREATE POLICY "Public timeline view"
    ON m2_timeline_posts FOR SELECT
    USING (status = 1);

DROP POLICY IF EXISTS "Authors manage own timeline" ON m2_timeline_posts;
CREATE POLICY "Authors manage own timeline"
    ON m2_timeline_posts FOR ALL
    USING (auth.uid() = user_id);

-- m2_photos: 公共可读，作者管理
DROP POLICY IF EXISTS "Public photos view" ON m2_photos;
CREATE POLICY "Public photos view"
    ON m2_photos FOR SELECT
    USING (status = 1);

DROP POLICY IF EXISTS "Authors manage own photos" ON m2_photos;
CREATE POLICY "Authors manage own photos"
    ON m2_photos FOR ALL
    USING (auth.uid() = user_id);

-- m2_comments: 公共读取，用户管理自己
DROP POLICY IF EXISTS "Public comments view" ON m2_comments;
CREATE POLICY "Public comments view"
    ON m2_comments FOR SELECT
    USING (status = 1);

DROP POLICY IF EXISTS "Users manage own comments" ON m2_comments;
CREATE POLICY "Users manage own comments"
    ON m2_comments FOR ALL
    USING (auth.uid() = user_id);

-- m2_likes: 用户管理自己的点赞
DROP POLICY IF EXISTS "Users manage own likes" ON m2_likes;
CREATE POLICY "Users manage own likes"
    ON m2_likes FOR ALL
    USING (auth.uid() = user_id);

-- m2_bookmarks: 用户管理自己的收藏
DROP POLICY IF EXISTS "Users manage own bookmarks" ON m2_bookmarks;
CREATE POLICY "Users manage own bookmarks"
    ON m2_bookmarks FOR ALL
    USING (auth.uid() = user_id);

-- m2_shares: 用户管理自己的分享记录
DROP POLICY IF EXISTS "Users manage own shares" ON m2_shares;
CREATE POLICY "Users manage own shares"
    ON m2_shares FOR ALL
    USING (auth.uid() = user_id);

-- m2_messages: 公开读取，相关用户管理
DROP POLICY IF EXISTS "Public messages view" ON m2_messages;
CREATE POLICY "Public messages view"
    ON m2_messages FOR SELECT
    USING (is_public = TRUE);

DROP POLICY IF EXISTS "Users manage own messages" ON m2_messages;
CREATE POLICY "Users manage own messages"
    ON m2_messages FOR ALL
    USING (auth.uid() = user_id OR auth.uid() = author_id);

-- m2_sponsorships: 自己和作者可读
DROP POLICY IF EXISTS "Users view related sponsorships" ON m2_sponsorships;
CREATE POLICY "Users view related sponsorships"
    ON m2_sponsorships FOR SELECT
    USING (auth.uid() = user_id OR auth.uid() = author_id);

DROP POLICY IF EXISTS "Users manage own sponsorships" ON m2_sponsorships;
CREATE POLICY "Users manage own sponsorships"
    ON m2_sponsorships FOR ALL
    USING (auth.uid() = user_id);

-- m2_notifications: 用户查看并更新自己的通知
DROP POLICY IF EXISTS "Users manage own notifications" ON m2_notifications;
CREATE POLICY "Users manage own notifications"
    ON m2_notifications FOR ALL
    USING (auth.uid() = user_id);

-- m2_system_configs: 公共配置可读，管理员管理
DROP POLICY IF EXISTS "Public configs view" ON m2_system_configs;
CREATE POLICY "Public configs view"
    ON m2_system_configs FOR SELECT
    USING (is_public = TRUE);

DROP POLICY IF EXISTS "Admins manage configs" ON m2_system_configs;
CREATE POLICY "Admins manage configs"
    ON m2_system_configs FOR ALL
    USING (
        auth.role() = 'authenticated' AND
        EXISTS (
            SELECT 1 FROM m2_users u
            WHERE u.id = auth.uid() AND u.role = 'admin'
        )
    );

-- -----------------------------------------------------
-- 11. 默认数据
-- -----------------------------------------------------

INSERT INTO m2_system_configs (config_key, config_value, config_type, is_public, description)
VALUES
    ('site.title', '旅行轨迹记录平台', 'text', TRUE, '站点标题'),
    ('site.description', '记录旅途，分享精彩瞬间', 'text', TRUE, '站点描述'),
    ('site.language', 'zh-CN', 'text', TRUE, '默认语言'),
    ('track.default_zoom', '4', 'number', TRUE, '轨迹地图默认缩放等级'),
    ('sponsorship.enabled', 'true', 'boolean', FALSE, '赞助功能开关')
ON CONFLICT (config_key) DO NOTHING;

-- 自动为 auth.users 新增用户生成 m2_users 记录
CREATE OR REPLACE FUNCTION fn_create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO m2_users (id, username, display_name, avatar_url)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'username', NEW.email), NEW.raw_user_meta_data->>'display_name', NEW.raw_user_meta_data->>'avatar_url')
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

-- -----------------------------------------------------
-- 12. 维护计划
-- -----------------------------------------------------

-- 创建定时任务刷新统计 (使用 Supabase pg_cron 或外部调度)
-- 示例: 每日 02:00 刷新所有用户统计
-- SELECT cron.schedule('refresh_user_stats_daily', '0 2 * * *', $$
--     SELECT fn_refresh_user_travel_stats(id) FROM m2_users;
-- $$);

-- -----------------------------------------------------
-- 脚本结束
-- -----------------------------------------------------

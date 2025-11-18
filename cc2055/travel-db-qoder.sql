-- =====================================================
-- 旅行轨迹记录网站 - Supabase生产环境数据库脚本
-- Travel Tracker Database Schema for Supabase
-- =====================================================
-- 版本: v2.0
-- 创建时间: 2025-11-16
-- 技术栈: Supabase + PostgreSQL 14+ + PostGIS
-- 表前缀: m2_
-- =====================================================

-- 设置时区
SET timezone = 'Asia/Shanghai';

-- =====================================================
-- 1. 启用必要的PostgreSQL扩展
-- =====================================================

-- UUID生成扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 地理数据处理扩展（PostGIS）
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 文本搜索优化扩展
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 性能监控扩展
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- 创建中文全文搜索配置（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_ts_config WHERE cfgname = 'chinese'
    ) THEN
        CREATE TEXT SEARCH CONFIGURATION chinese (COPY = simple);
    END IF;
END $$;

-- =====================================================
-- 2. 用户系统表 (User System)
-- =====================================================

-- -----------------------------------------------------
-- 2.1 用户基础信息表 (m2_users)
-- 说明: 存储用户基本信息，与auth.users关联
-- 关联: auth.users.id = m2_users.id
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_users (
    -- 主键，与Supabase Auth的user_id一致
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- 基础认证信息
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(20) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    
    -- 用户资料
    avatar VARCHAR(255),
    nickname VARCHAR(50),
    gender SMALLINT DEFAULT 0 CHECK (gender IN (0, 1, 2)), -- 0-未知, 1-男, 2-女
    birthdate DATE,
    bio TEXT,
    
    -- 登录信息
    last_login_ip INET,
    last_login_time TIMESTAMPTZ,
    
    -- 用户类型
    is_author BOOLEAN DEFAULT FALSE, -- 是否为作者（可发布内容）
    
    -- 状态管理
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1)), -- 0-禁用, 1-正常
    
    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 约束
    CONSTRAINT username_format CHECK (username ~ '^[a-zA-Z][a-zA-Z0-9_]*$'),
    CONSTRAINT email_format CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_users_username ON m2_users(username);
CREATE INDEX IF NOT EXISTS idx_m2_users_email ON m2_users(email);
CREATE INDEX IF NOT EXISTS idx_m2_users_status ON m2_users(status);
CREATE INDEX IF NOT EXISTS idx_m2_users_created_at ON m2_users(created_at);

-- 添加表注释
COMMENT ON TABLE m2_users IS '用户基础信息表，存储用户的基本资料和状态';
COMMENT ON COLUMN m2_users.id IS '用户ID，与Supabase Auth的UUID一致';
COMMENT ON COLUMN m2_users.is_author IS '是否为作者，只有作者可以发布内容和生成轨迹点';
COMMENT ON COLUMN m2_users.status IS '用户状态：0-禁用, 1-正常';

-- -----------------------------------------------------
-- 2.2 用户会话表 (m2_user_sessions)
-- 说明: 管理用户登录会话（补充Supabase Auth）
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 会话信息
    token VARCHAR(255) NOT NULL UNIQUE,
    device_info VARCHAR(255),
    ip_address INET,
    
    -- 时间管理
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_activity TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_user_sessions_user_id ON m2_user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_user_sessions_token ON m2_user_sessions(token);
CREATE INDEX IF NOT EXISTS idx_m2_user_sessions_expires_at ON m2_user_sessions(expires_at);

COMMENT ON TABLE m2_user_sessions IS '用户会话表，记录登录会话信息';

-- -----------------------------------------------------
-- 2.3 用户旅行统计表 (m2_user_travel_stats)
-- 说明: 存储用户旅行数据的统计信息
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_user_travel_stats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 旅行数据统计
    total_distance DECIMAL(12, 2) DEFAULT 0, -- 总公里数
    total_days INTEGER DEFAULT 0, -- 总天数
    cities_count INTEGER DEFAULT 0, -- 途径城市数
    
    -- 内容数量统计
    articles_count INTEGER DEFAULT 0, -- 文章数
    timeline_posts_count INTEGER DEFAULT 0, -- 时光轴数
    photos_count INTEGER DEFAULT 0, -- 照片数
    
    -- 互动数据统计
    total_likes_received INTEGER DEFAULT 0, -- 总获赞数
    total_comments_received INTEGER DEFAULT 0, -- 总评论数
    total_views INTEGER DEFAULT 0, -- 总浏览数
    
    -- 社交数据统计
    followers_count INTEGER DEFAULT 0, -- 粉丝数
    
    -- 更新时间
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    
    -- 唯一约束：每个用户只有一条统计记录
    UNIQUE(user_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_user_travel_stats_user_id ON m2_user_travel_stats(user_id);

COMMENT ON TABLE m2_user_travel_stats IS '用户旅行统计表，自动计算和更新用户的各项旅行数据';
COMMENT ON COLUMN m2_user_travel_stats.total_distance IS '总公里数，从所有已发布文章的travel_distance字段累加';
COMMENT ON COLUMN m2_user_travel_stats.total_days IS '旅行总天数，从最早到最晚的旅行日期计算';
COMMENT ON COLUMN m2_user_travel_stats.cities_count IS '途径城市数，从文章和时光轴的地址字段去重统计';

-- -----------------------------------------------------
-- 2.4 用户关注表 (m2_user_follows)
-- 说明: 存储用户之间的关注关系
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_user_follows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    follower_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE, -- 关注者
    following_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE, -- 被关注者
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 唯一约束：防止重复关注
    UNIQUE(follower_id, following_id),
    
    -- 约束：不能关注自己
    CONSTRAINT not_self_follow CHECK (follower_id <> following_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_user_follows_follower_id ON m2_user_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_m2_user_follows_following_id ON m2_user_follows(following_id);

COMMENT ON TABLE m2_user_follows IS '用户关注关系表，记录用户之间的关注关系';

-- =====================================================
-- 3. 轨迹系统表 (Track System)
-- =====================================================

-- -----------------------------------------------------
-- 3.1 轨迹点表 (m2_track_points)
-- 说明: 存储所有轨迹点信息，从文章/时光轴/照片自动生成
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_track_points (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 地理位置信息
    latitude DECIMAL(10, 8) NOT NULL, -- 纬度
    longitude DECIMAL(11, 8) NOT NULL, -- 经度
    address VARCHAR(255), -- 详细地址
    
    -- 轨迹点类型和关联
    point_type SMALLINT NOT NULL CHECK (point_type IN (1, 2, 3)), -- 1-文章, 2-时光轴, 3-照片
    related_id UUID NOT NULL, -- 关联的内容ID
    
    -- 时间和状态
    create_time TIMESTAMPTZ NOT NULL,
    is_public BOOLEAN DEFAULT TRUE -- 是否公开显示
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_track_points_user_id ON m2_track_points(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_track_points_type ON m2_track_points(point_type);
CREATE INDEX IF NOT EXISTS idx_m2_track_points_create_time ON m2_track_points(create_time);

-- PostGIS地理索引（用于空间查询）
CREATE INDEX IF NOT EXISTS idx_m2_track_points_location ON m2_track_points 
    USING GIST (ST_Point(longitude, latitude));

COMMENT ON TABLE m2_track_points IS '轨迹点表，存储用户旅行轨迹的所有点位信息';
COMMENT ON COLUMN m2_track_points.point_type IS '轨迹点类型：1-文章, 2-时光轴, 3-照片';
COMMENT ON COLUMN m2_track_points.related_id IS '关联的内容ID，根据point_type指向不同表';

-- -----------------------------------------------------
-- 3.2 轨迹段表 (m2_track_segments)
-- 说明: 存储轨迹点之间的连接线段
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_track_segments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 起点和终点
    start_point_id UUID NOT NULL REFERENCES m2_track_points(id) ON DELETE CASCADE,
    end_point_id UUID NOT NULL REFERENCES m2_track_points(id) ON DELETE CASCADE,
    
    -- 段信息
    distance DECIMAL(10, 2) NOT NULL, -- 距离（公里）
    duration INTEGER, -- 时长（分钟）
    segment_order INTEGER NOT NULL, -- 顺序号
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 约束：起点和终点不能相同
    CONSTRAINT different_points CHECK (start_point_id <> end_point_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_track_segments_user_id ON m2_track_segments(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_track_segments_order ON m2_track_segments(user_id, segment_order);

COMMENT ON TABLE m2_track_segments IS '轨迹段表，连接轨迹点形成完整的旅行路径';

-- =====================================================
-- 4. 内容管理表 (Content Management)
-- =====================================================

-- -----------------------------------------------------
-- 4.1 文章分类表 (m2_article_categories)
-- 说明: 文章分类字典表
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_article_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    display_order INTEGER DEFAULT 0, -- 显示顺序
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1)), -- 0-禁用, 1-正常
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 插入默认分类
INSERT INTO m2_article_categories (name, description, display_order) VALUES
('旅行日记', '详细的旅行记录和经历分享', 1),
('同行故事', '与他人一起旅行的故事和回忆', 2),
('心情文字', '旅行过程中的心情记录和感悟', 3),
('城市记忆', '对特定城市的印象和记忆', 4)
ON CONFLICT (name) DO NOTHING;

COMMENT ON TABLE m2_article_categories IS '文章分类表，预定义的文章分类';

-- -----------------------------------------------------
-- 4.2 旅行文章表 (m2_articles)
-- 说明: 存储旅行文章的详细信息
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_articles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES m2_article_categories(id) ON DELETE SET NULL,
    
    -- 文章内容
    title VARCHAR(200) NOT NULL,
    summary TEXT,
    content TEXT NOT NULL, -- 支持Markdown格式
    cover_image VARCHAR(255),
    
    -- 旅行信息
    travel_date DATE, -- 旅行日期
    travel_method VARCHAR(50), -- 旅行方式：驾车/骑行/徒步/火车/飞机等
    travel_distance DECIMAL(10, 2), -- 公里数
    
    -- 地理位置
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    address VARCHAR(255),
    show_on_track BOOLEAN DEFAULT TRUE, -- 是否在轨迹图显示
    
    -- 互动数据
    view_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    
    -- 扩展信息
    mood_score INTEGER CHECK (mood_score BETWEEN 1 AND 5), -- 心情评分
    weather VARCHAR(20), -- 天气状况
    weight DECIMAL(5, 2), -- 体重(kg)
    recommendation_rating INTEGER CHECK (recommendation_rating BETWEEN 1 AND 5), -- 推荐指数
    
    -- 扩展字段（JSON格式存储住宿、交通等信息）
    extension_fields JSONB,
    
    -- 标签
    tags TEXT[], -- 标签数组
    
    -- 状态管理
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1, 2)), -- 0-草稿, 1-已发布, 2-已删除
    
    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    published_at TIMESTAMPTZ
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_articles_user_id ON m2_articles(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_articles_category_id ON m2_articles(category_id);
CREATE INDEX IF NOT EXISTS idx_m2_articles_status ON m2_articles(status);
CREATE INDEX IF NOT EXISTS idx_m2_articles_published_at ON m2_articles(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_m2_articles_travel_date ON m2_articles(travel_date);

-- GIN索引：标签数组
CREATE INDEX IF NOT EXISTS idx_m2_articles_tags ON m2_articles USING GIN (tags);

-- PostGIS地理索引
CREATE INDEX IF NOT EXISTS idx_m2_articles_location ON m2_articles 
    USING GIST (ST_Point(longitude, latitude));

-- 全文搜索索引（中文）
CREATE INDEX IF NOT EXISTS idx_m2_articles_content_search ON m2_articles 
    USING GIN (to_tsvector('chinese', title || ' ' || COALESCE(summary, '') || ' ' || content));

-- 数据约束
ALTER TABLE m2_articles ADD CONSTRAINT check_article_title_not_empty 
    CHECK (LENGTH(TRIM(title)) > 0);

COMMENT ON TABLE m2_articles IS '旅行文章表，存储详细的旅行游记和博客';
COMMENT ON COLUMN m2_articles.show_on_track IS '是否在轨迹图上显示此文章的定位点';
COMMENT ON COLUMN m2_articles.extension_fields IS 'JSON扩展字段，存储住宿、交通等自定义信息';

-- -----------------------------------------------------
-- 4.3 专题表 (m2_special_topics)
-- 说明: 组织和分类旅行文章的专题容器
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_special_topics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 专题信息
    title VARCHAR(200) NOT NULL,
    description TEXT,
    cover_image VARCHAR(255),
    tags TEXT[],
    
    -- 统计
    article_count INTEGER DEFAULT 0,
    
    -- 状态
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1, 2)), -- 0-草稿, 1-已发布, 2-已删除
    
    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_special_topics_user_id ON m2_special_topics(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_special_topics_status ON m2_special_topics(status);
CREATE INDEX IF NOT EXISTS idx_m2_special_topics_tags ON m2_special_topics USING GIN (tags);

COMMENT ON TABLE m2_special_topics IS '专题表，用于组织多篇相关的旅行文章';

-- -----------------------------------------------------
-- 4.4 专题文章关联表 (m2_topic_article_relations)
-- 说明: 专题与文章的多对多关系
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_topic_article_relations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    topic_id UUID NOT NULL REFERENCES m2_special_topics(id) ON DELETE CASCADE,
    article_id UUID NOT NULL REFERENCES m2_articles(id) ON DELETE CASCADE,
    display_order INTEGER DEFAULT 0, -- 在专题中的显示顺序
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 唯一约束：防止重复关联
    UNIQUE(topic_id, article_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_topic_article_relations_topic_id ON m2_topic_article_relations(topic_id);
CREATE INDEX IF NOT EXISTS idx_m2_topic_article_relations_article_id ON m2_topic_article_relations(article_id);
CREATE INDEX IF NOT EXISTS idx_m2_topic_article_relations_order ON m2_topic_article_relations(topic_id, display_order);

COMMENT ON TABLE m2_topic_article_relations IS '专题文章关联表，建立专题和文章的多对多关系';

-- -----------------------------------------------------
-- 4.5 时光轴动态表 (m2_timeline_posts)
-- 说明: 存储类似微博/朋友圈的短动态
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_timeline_posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 动态内容
    content VARCHAR(500) NOT NULL, -- 文字内容（最多500字）
    milestone VARCHAR(100), -- 里程碑标记，如"到达拉萨"
    mood_tag VARCHAR(50), -- 心情标签
    weather_tag VARCHAR(20), -- 天气标签
    
    -- 地理位置
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    address VARCHAR(255),
    show_on_track BOOLEAN DEFAULT TRUE, -- 是否在轨迹图显示
    
    -- 互动数据
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    
    -- 关联
    related_article_id UUID REFERENCES m2_articles(id) ON DELETE SET NULL, -- 关联的文章
    
    -- 扩展字段
    extension_fields JSONB,
    
    -- 图片（1-9张）
    images JSONB, -- 存储图片URL数组
    
    -- 状态
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1)), -- 0-已删除, 1-正常
    
    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_user_id ON m2_timeline_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_created_at ON m2_timeline_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_status ON m2_timeline_posts(status);

-- PostGIS地理索引
CREATE INDEX IF NOT EXISTS idx_m2_timeline_posts_location ON m2_timeline_posts 
    USING GIST (ST_Point(longitude, latitude));

-- 数据约束
ALTER TABLE m2_timeline_posts ADD CONSTRAINT check_timeline_content_not_empty 
    CHECK (LENGTH(TRIM(content)) > 0);

COMMENT ON TABLE m2_timeline_posts IS '时光轴动态表，存储轻量级的旅行动态和心情';
COMMENT ON COLUMN m2_timeline_posts.images IS 'JSON数组，存储1-9张图片的URL';

-- -----------------------------------------------------
-- 4.6 照片表 (m2_photos)
-- 说明: 独立的照片管理系统
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 文件信息
    file_url VARCHAR(255) NOT NULL,
    thumbnail_url VARCHAR(255), -- 缩略图
    width INTEGER,
    height INTEGER,
    size BIGINT, -- 文件大小（bytes）
    
    -- 照片信息
    description VARCHAR(255),
    
    -- 地理位置
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    address VARCHAR(255),
    shoot_date TIMESTAMPTZ, -- 拍摄时间
    show_on_track BOOLEAN DEFAULT TRUE,
    
    -- 分类和标签
    category VARCHAR(50) DEFAULT 'other', -- 风景/美食/人物/文化/其他
    tags TEXT[],
    
    -- 状态
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1)), -- 0-已删除, 1-正常
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_photos_user_id ON m2_photos(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_photos_category ON m2_photos(category);
CREATE INDEX IF NOT EXISTS idx_m2_photos_status ON m2_photos(status);
CREATE INDEX IF NOT EXISTS idx_m2_photos_shoot_date ON m2_photos(shoot_date);
CREATE INDEX IF NOT EXISTS idx_m2_photos_tags ON m2_photos USING GIN (tags);

-- PostGIS地理索引
CREATE INDEX IF NOT EXISTS idx_m2_photos_location ON m2_photos 
    USING GIST (ST_Point(longitude, latitude));

COMMENT ON TABLE m2_photos IS '照片表，独立管理所有旅行照片';
COMMENT ON COLUMN m2_photos.category IS '照片分类：风景/美食/人物/文化/其他';

-- -----------------------------------------------------
-- 4.7 时光轴照片关联表 (m2_timeline_photo_relations)
-- 说明: 时光轴与照片的关联关系
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_timeline_photo_relations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timeline_id UUID NOT NULL REFERENCES m2_timeline_posts(id) ON DELETE CASCADE,
    photo_id UUID NOT NULL REFERENCES m2_photos(id) ON DELETE CASCADE,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(timeline_id, photo_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_timeline_photo_relations_timeline_id ON m2_timeline_photo_relations(timeline_id);
CREATE INDEX IF NOT EXISTS idx_m2_timeline_photo_relations_photo_id ON m2_timeline_photo_relations(photo_id);
CREATE INDEX IF NOT EXISTS idx_m2_timeline_photo_relations_order ON m2_timeline_photo_relations(timeline_id, display_order);

COMMENT ON TABLE m2_timeline_photo_relations IS '时光轴照片关联表';

-- =====================================================
-- 5. 社交互动表 (Social Interaction)
-- =====================================================

-- -----------------------------------------------------
-- 5.1 评论表 (m2_comments)
-- 说明: 存储所有内容的评论，支持嵌套回复
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 评论目标
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 3)), -- 1-文章, 2-时光轴, 3-照片
    target_id UUID NOT NULL,
    
    -- 回复关系
    parent_id UUID REFERENCES m2_comments(id) ON DELETE CASCADE, -- 父评论ID（回复时使用）
    
    -- 评论内容
    content TEXT NOT NULL,
    
    -- 互动
    like_count INTEGER DEFAULT 0,
    
    -- 状态
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1, 2)), -- 0-已删除, 1-正常, 2-已隐藏
    
    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_comments_user_id ON m2_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_comments_target ON m2_comments(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_m2_comments_parent_id ON m2_comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_m2_comments_created_at ON m2_comments(created_at);

-- 数据约束
ALTER TABLE m2_comments ADD CONSTRAINT check_comment_content_not_empty 
    CHECK (LENGTH(TRIM(content)) > 0);

COMMENT ON TABLE m2_comments IS '评论表，支持对文章/时光轴/照片的评论和嵌套回复';

-- -----------------------------------------------------
-- 5.2 点赞表 (m2_likes)
-- 说明: 存储所有内容的点赞记录
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_likes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 点赞目标
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 3, 4)), -- 1-文章, 2-时光轴, 3-评论, 4-照片
    target_id UUID NOT NULL,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 唯一约束：防止重复点赞
    UNIQUE(user_id, target_type, target_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_likes_user_id ON m2_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_likes_target ON m2_likes(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_m2_likes_created_at ON m2_likes(created_at);

COMMENT ON TABLE m2_likes IS '点赞表，记录用户对各类内容的点赞';

-- -----------------------------------------------------
-- 5.3 收藏表 (m2_bookmarks)
-- 说明: 存储用户收藏的内容
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_bookmarks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE,
    
    -- 收藏目标
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 3)), -- 1-文章, 2-时光轴, 3-专题
    target_id UUID NOT NULL,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 唯一约束：防止重复收藏
    UNIQUE(user_id, target_type, target_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_bookmarks_user_id ON m2_bookmarks(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_bookmarks_target ON m2_bookmarks(target_type, target_id);

COMMENT ON TABLE m2_bookmarks IS '收藏表，记录用户收藏的内容';

-- -----------------------------------------------------
-- 5.4 分享表 (m2_shares)
-- 说明: 存储内容分享记录
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_shares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES m2_users(id) ON DELETE SET NULL, -- 游客分享时可能为空
    
    -- 分享目标
    target_type SMALLINT NOT NULL CHECK (target_type IN (1, 2, 3)), -- 1-文章, 2-时光轴, 3-专题
    target_id UUID NOT NULL,
    
    -- 分享信息
    share_platform VARCHAR(50), -- wechat/weibo/qq/link等
    share_message TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_shares_target ON m2_shares(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_m2_shares_created_at ON m2_shares(created_at);

COMMENT ON TABLE m2_shares IS '分享表，记录内容的分享行为';

-- =====================================================
-- 6. 留言墙与赞助表 (Message Wall & Sponsorship)
-- =====================================================

-- -----------------------------------------------------
-- 6.1 留言表 (m2_messages)
-- 说明: 留言墙功能，用户给作者留言
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES m2_users(id) ON DELETE SET NULL, -- 留言者（游客可为空）
    author_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE, -- 接收留言的作者
    
    -- 留言内容
    content TEXT NOT NULL,
    
    -- 留言位置
    location_name VARCHAR(255),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    
    -- 作者回复
    reply_content TEXT,
    reply_time TIMESTAMPTZ,
    
    -- 状态
    status SMALLINT DEFAULT 1 CHECK (status IN (0, 1, 2)), -- 0-已删除, 1-正常, 2-已隐藏
    is_hidden BOOLEAN DEFAULT FALSE,
    
    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_messages_author_id ON m2_messages(author_id);
CREATE INDEX IF NOT EXISTS idx_m2_messages_user_id ON m2_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_messages_created_at ON m2_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_m2_messages_status ON m2_messages(status);

-- 数据约束
ALTER TABLE m2_messages ADD CONSTRAINT check_message_content_not_empty 
    CHECK (LENGTH(TRIM(content)) > 0);

COMMENT ON TABLE m2_messages IS '留言墙表，用户可以给作者留言';

-- -----------------------------------------------------
-- 6.2 赞助表 (m2_sponsorships)
-- 说明: 赞助/打赏功能
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_sponsorships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES m2_users(id) ON DELETE SET NULL, -- 赞助者（游客可为空）
    author_id UUID NOT NULL REFERENCES m2_users(id) ON DELETE CASCADE, -- 被赞助的作者
    
    -- 赞助金额
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'CNY',
    
    -- 赞助信息
    message TEXT, -- 赞助留言
    is_anonymous BOOLEAN DEFAULT FALSE, -- 是否匿名
    sponsor_nickname VARCHAR(50), -- 匿名时的昵称
    badge_type VARCHAR(50), -- 徽章类型：铁杆粉丝/金主等
    
    -- 支付信息
    payment_status SMALLINT DEFAULT 0 CHECK (payment_status IN (0, 1, 2, 3)), -- 0-待支付, 1-已支付, 2-已取消, 3-已退款
    payment_method VARCHAR(50), -- alipay/wechat
    transaction_id VARCHAR(100), -- 交易流水号
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_m2_sponsorships_author_id ON m2_sponsorships(author_id);
CREATE INDEX IF NOT EXISTS idx_m2_sponsorships_user_id ON m2_sponsorships(user_id);
CREATE INDEX IF NOT EXISTS idx_m2_sponsorships_created_at ON m2_sponsorships(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_m2_sponsorships_payment_status ON m2_sponsorships(payment_status);

-- 数据约束
ALTER TABLE m2_sponsorships ADD CONSTRAINT check_sponsorship_amount_positive 
    CHECK (amount > 0);

COMMENT ON TABLE m2_sponsorships IS '赞助表，记录用户对作者的赞助/打赏';

-- =====================================================
-- 7. 系统配置表 (System Configuration)
-- =====================================================

-- -----------------------------------------------------
-- 7.1 系统配置表 (m2_system_configs)
-- 说明: 存储系统级配置信息
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS m2_system_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    config_key VARCHAR(100) NOT NULL UNIQUE,
    config_value TEXT,
    config_type VARCHAR(50) DEFAULT 'string', -- string/number/boolean/json
    description TEXT,
    is_public BOOLEAN DEFAULT FALSE, -- 是否公开显示
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 插入默认配置
INSERT INTO m2_system_configs (config_key, config_value, config_type, description, is_public) VALUES
('site_name', '旅行轨迹记录平台', 'string', '网站名称', TRUE),
('site_description', '个人旅行轨迹记录与分享平台', 'string', '网站描述', TRUE),
('max_upload_size', '10485760', 'number', '最大上传文件大小(字节)', FALSE),
('allowed_image_types', '["jpg", "jpeg", "png", "gif", "webp"]', 'json', '允许的图片格式', FALSE),
('timeline_max_images', '9', 'number', '时光轴最多上传图片数', TRUE)
ON CONFLICT (config_key) DO NOTHING;

COMMENT ON TABLE m2_system_configs IS '系统配置表，存储全局配置信息';

-- =====================================================
-- 8. 触发器函数 (Trigger Functions)
-- =====================================================

-- -----------------------------------------------------
-- 8.1 自动更新时间戳函数
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_updated_at_column() IS '自动更新updated_at字段为当前时间';

-- 为需要的表添加更新时间戳触发器
CREATE TRIGGER update_m2_users_updated_at 
    BEFORE UPDATE ON m2_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_m2_articles_updated_at 
    BEFORE UPDATE ON m2_articles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_m2_special_topics_updated_at 
    BEFORE UPDATE ON m2_special_topics
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_m2_timeline_posts_updated_at 
    BEFORE UPDATE ON m2_timeline_posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_m2_comments_updated_at 
    BEFORE UPDATE ON m2_comments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_m2_messages_updated_at 
    BEFORE UPDATE ON m2_messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_m2_system_configs_updated_at 
    BEFORE UPDATE ON m2_system_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------
-- 8.2 用户注册时自动创建统计记录
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION create_user_stats()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO m2_user_travel_stats (user_id) 
    VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_user_stats() IS '用户注册时自动创建统计记录';

CREATE TRIGGER create_user_stats_trigger
    AFTER INSERT ON m2_users
    FOR EACH ROW EXECUTE FUNCTION create_user_stats();

-- -----------------------------------------------------
-- 8.3 自动创建轨迹点
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION create_track_point()
RETURNS TRIGGER AS $$
BEGIN
    -- 如果设置为在轨迹图显示且有位置信息
    IF (NEW.show_on_track = TRUE AND NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL) THEN
        -- 根据表名判断point_type
        IF TG_TABLE_NAME = 'm2_articles' THEN
            INSERT INTO m2_track_points (
                user_id, latitude, longitude, address, 
                point_type, related_id, create_time
            ) VALUES (
                NEW.user_id, NEW.latitude, NEW.longitude, NEW.address,
                1, -- 文章类型
                NEW.id, NEW.created_at
            );
        ELSIF TG_TABLE_NAME = 'm2_timeline_posts' THEN
            INSERT INTO m2_track_points (
                user_id, latitude, longitude, address, 
                point_type, related_id, create_time
            ) VALUES (
                NEW.user_id, NEW.latitude, NEW.longitude, NEW.address,
                2, -- 时光轴类型
                NEW.id, NEW.created_at
            );
        ELSIF TG_TABLE_NAME = 'm2_photos' THEN
            INSERT INTO m2_track_points (
                user_id, latitude, longitude, address, 
                point_type, related_id, create_time
            ) VALUES (
                NEW.user_id, NEW.latitude, NEW.longitude, NEW.address,
                3, -- 照片类型
                NEW.id, NEW.created_at
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_track_point() IS '发布内容时自动创建轨迹点';

-- 为文章、时光轴、照片表添加触发器
CREATE TRIGGER create_article_track_point_trigger
    AFTER INSERT OR UPDATE ON m2_articles
    FOR EACH ROW EXECUTE FUNCTION create_track_point();

CREATE TRIGGER create_timeline_track_point_trigger
    AFTER INSERT OR UPDATE ON m2_timeline_posts
    FOR EACH ROW EXECUTE FUNCTION create_track_point();

CREATE TRIGGER create_photo_track_point_trigger
    AFTER INSERT OR UPDATE ON m2_photos
    FOR EACH ROW EXECUTE FUNCTION create_track_point();

-- -----------------------------------------------------
-- 8.4 更新用户统计信息函数
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION update_user_stats(user_uuid UUID)
RETURNS VOID AS $$
DECLARE
    total_distance_val DECIMAL(12, 2);
    total_days_val INTEGER;
    cities_val INTEGER;
    articles_val INTEGER;
    timeline_val INTEGER;
    photos_val INTEGER;
    likes_val INTEGER;
    comments_val INTEGER;
    views_val INTEGER;
BEGIN
    -- 计算总公里数（从文章表）
    SELECT COALESCE(SUM(travel_distance), 0) INTO total_distance_val
    FROM m2_articles 
    WHERE user_id = user_uuid AND status = 1;
    
    -- 计算总天数
    SELECT COALESCE(
        EXTRACT(DAY FROM (MAX(travel_date) - MIN(travel_date))) + 1, 
        0
    ) INTO total_days_val
    FROM m2_articles 
    WHERE user_id = user_uuid AND status = 1 AND travel_date IS NOT NULL;
    
    -- 计算途径城市数（去重）
    SELECT COUNT(DISTINCT address) INTO cities_val
    FROM (
        SELECT address FROM m2_articles 
        WHERE user_id = user_uuid AND status = 1 AND address IS NOT NULL
        UNION
        SELECT address FROM m2_timeline_posts 
        WHERE user_id = user_uuid AND status = 1 AND address IS NOT NULL
    ) locations
    WHERE address IS NOT NULL AND address != '';
    
    -- 统计各类内容数量
    SELECT COUNT(*) INTO articles_val FROM m2_articles WHERE user_id = user_uuid AND status = 1;
    SELECT COUNT(*) INTO timeline_val FROM m2_timeline_posts WHERE user_id = user_uuid AND status = 1;
    SELECT COUNT(*) INTO photos_val FROM m2_photos WHERE user_id = user_uuid AND status = 1;
    
    -- 统计互动数据
    SELECT COALESCE(SUM(like_count), 0) INTO likes_val
    FROM (
        SELECT like_count FROM m2_articles WHERE user_id = user_uuid AND status = 1
        UNION ALL
        SELECT like_count FROM m2_timeline_posts WHERE user_id = user_uuid AND status = 1
    ) likes_table;
    
    SELECT COALESCE(SUM(comment_count), 0) INTO comments_val
    FROM (
        SELECT comment_count FROM m2_articles WHERE user_id = user_uuid AND status = 1
        UNION ALL
        SELECT comment_count FROM m2_timeline_posts WHERE user_id = user_uuid AND status = 1
    ) comments_table;
    
    SELECT COALESCE(SUM(view_count), 0) INTO views_val 
    FROM m2_articles WHERE user_id = user_uuid AND status = 1;
    
    -- 更新或插入统计记录
    INSERT INTO m2_user_travel_stats (
        user_id, total_distance, total_days, cities_count, 
        articles_count, timeline_posts_count, photos_count,
        total_likes_received, total_comments_received, total_views, last_updated
    ) VALUES (
        user_uuid, total_distance_val, total_days_val, cities_val,
        articles_val, timeline_val, photos_val,
        likes_val, comments_val, views_val, NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        total_distance = EXCLUDED.total_distance,
        total_days = EXCLUDED.total_days,
        cities_count = EXCLUDED.cities_count,
        articles_count = EXCLUDED.articles_count,
        timeline_posts_count = EXCLUDED.timeline_posts_count,
        photos_count = EXCLUDED.photos_count,
        total_likes_received = EXCLUDED.total_likes_received,
        total_comments_received = EXCLUDED.total_comments_received,
        total_views = EXCLUDED.total_views,
        last_updated = EXCLUDED.last_updated;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_user_stats(UUID) IS '更新指定用户的旅行统计数据';

-- =====================================================
-- 9. Row Level Security (RLS) 策略
-- =====================================================

-- -----------------------------------------------------
-- 9.1 启用RLS
-- -----------------------------------------------------
ALTER TABLE m2_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_track_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_track_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_special_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_topic_article_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_timeline_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_timeline_photo_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_sponsorships ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_user_travel_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_user_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE m2_article_categories ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------
-- 9.2 用户表策略
-- -----------------------------------------------------
-- 用户可以查看和更新自己的资料
CREATE POLICY "Users can view and update own profile" ON m2_users
    FOR ALL USING (auth.uid() = id);

-- 所有人可以查看正常状态用户的公开信息
CREATE POLICY "Public user profiles are viewable" ON m2_users
    FOR SELECT USING (status = 1);

-- -----------------------------------------------------
-- 9.3 会话表策略
-- -----------------------------------------------------
CREATE POLICY "Users can view own sessions" ON m2_user_sessions
    FOR SELECT USING (auth.uid() = user_id);

-- -----------------------------------------------------
-- 9.4 内容表策略
-- -----------------------------------------------------
-- 所有人可以查看已发布的文章
CREATE POLICY "Public articles are viewable" ON m2_articles
    FOR SELECT USING (status = 1);

-- 作者可以管理自己的文章
CREATE POLICY "Authors can manage own articles" ON m2_articles
    FOR ALL USING (auth.uid() = user_id);

-- 所有人可以查看已发布的时光轴
CREATE POLICY "Public timeline posts are viewable" ON m2_timeline_posts
    FOR SELECT USING (status = 1);

-- 作者可以管理自己的时光轴
CREATE POLICY "Authors can manage own timeline posts" ON m2_timeline_posts
    FOR ALL USING (auth.uid() = user_id);

-- 所有人可以查看正常状态的照片
CREATE POLICY "Public photos are viewable" ON m2_photos
    FOR SELECT USING (status = 1);

-- 作者可以管理自己的照片
CREATE POLICY "Authors can manage own photos" ON m2_photos
    FOR ALL USING (auth.uid() = user_id);

-- 所有人可以查看已发布的专题
CREATE POLICY "Public special topics are viewable" ON m2_special_topics
    FOR SELECT USING (status = 1);

-- 作者可以管理自己的专题
CREATE POLICY "Authors can manage own special topics" ON m2_special_topics
    FOR ALL USING (auth.uid() = user_id);

-- -----------------------------------------------------
-- 9.5 社交互动策略
-- -----------------------------------------------------
-- 用户可以管理自己的点赞
CREATE POLICY "Users can manage own likes" ON m2_likes
    FOR ALL USING (auth.uid() = user_id);

-- 用户可以管理自己的评论
CREATE POLICY "Users can manage own comments" ON m2_comments
    FOR ALL USING (auth.uid() = user_id);

-- 所有人可以查看正常状态的评论
CREATE POLICY "Public comments are viewable" ON m2_comments
    FOR SELECT USING (status = 1);

-- 用户可以管理自己的收藏
CREATE POLICY "Users can manage own bookmarks" ON m2_bookmarks
    FOR ALL USING (auth.uid() = user_id);

-- 用户可以管理自己的关注
CREATE POLICY "Users can manage own follows" ON m2_user_follows
    FOR ALL USING (auth.uid() = follower_id);

-- =====================================================
-- 10. 数据视图 (Views)
-- =====================================================

-- -----------------------------------------------------
-- 10.1 用户基础信息视图
-- -----------------------------------------------------
CREATE OR REPLACE VIEW m2_user_profiles AS
SELECT 
    u.id,
    u.username,
    u.nickname,
    u.avatar,
    u.bio,
    u.is_author,
    u.created_at,
    stats.total_distance,
    stats.total_days,
    stats.cities_count,
    stats.articles_count,
    stats.timeline_posts_count,
    stats.photos_count,
    stats.total_likes_received,
    stats.total_comments_received,
    stats.followers_count
FROM m2_users u
LEFT JOIN m2_user_travel_stats stats ON u.id = stats.user_id
WHERE u.status = 1;

COMMENT ON VIEW m2_user_profiles IS '用户档案视图，展示用户基本信息和统计数据';

-- -----------------------------------------------------
-- 10.2 热门文章视图
-- -----------------------------------------------------
CREATE OR REPLACE VIEW m2_popular_articles AS
SELECT 
    a.id,
    a.user_id,
    u.nickname,
    u.avatar,
    a.title,
    a.summary,
    a.cover_image,
    a.travel_date,
    a.travel_method,
    a.address,
    a.view_count,
    a.like_count,
    a.comment_count,
    a.created_at,
    -- 热度计算：点赞40% + 评论30% + 浏览30%
    (a.like_count * 0.4 + a.comment_count * 0.3 + a.view_count * 0.3) AS popularity_score
FROM m2_articles a
JOIN m2_users u ON a.user_id = u.id
WHERE a.status = 1
ORDER BY popularity_score DESC;

COMMENT ON VIEW m2_popular_articles IS '热门文章视图，按热度排序';

-- -----------------------------------------------------
-- 10.3 精选专题视图
-- -----------------------------------------------------
CREATE OR REPLACE VIEW m2_featured_topics AS
SELECT 
    st.id,
    st.user_id,
    u.nickname,
    st.title,
    st.description,
    st.cover_image,
    st.article_count,
    st.created_at
FROM m2_special_topics st
JOIN m2_users u ON st.user_id = u.id
WHERE st.status = 1
ORDER BY st.article_count DESC, st.created_at DESC;

COMMENT ON VIEW m2_featured_topics IS '精选专题视图，按文章数量和创建时间排序';

-- =====================================================
-- 11. 初始化完成输出
-- =====================================================

DO $$
DECLARE
    table_count INTEGER;
    index_count INTEGER;
    trigger_count INTEGER;
BEGIN
    -- 统计创建的表数量
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name LIKE 'm2_%';
    
    -- 统计创建的索引数量
    SELECT COUNT(*) INTO index_count
    FROM pg_indexes 
    WHERE schemaname = 'public' 
    AND indexname LIKE 'idx_m2_%';
    
    -- 统计创建的触发器数量
    SELECT COUNT(*) INTO trigger_count
    FROM pg_trigger 
    WHERE tgname LIKE '%m2_%';
    
    RAISE NOTICE '=====================================================';
    RAISE NOTICE '旅行轨迹记录网站数据库初始化完成！';
    RAISE NOTICE '=====================================================';
    RAISE NOTICE '数据库版本: v2.0';
    RAISE NOTICE '创建表数量: %', table_count;
    RAISE NOTICE '创建索引数量: %', index_count;
    RAISE NOTICE '创建触发器数量: %', trigger_count;
    RAISE NOTICE '=====================================================';
    RAISE NOTICE '主要功能模块:';
    RAISE NOTICE '  ✅ 用户系统 (认证、统计、关注)';
    RAISE NOTICE '  ✅ 轨迹系统 (轨迹点、轨迹段)';
    RAISE NOTICE '  ✅ 内容管理 (文章、专题、时光轴、照片)';
    RAISE NOTICE '  ✅ 社交互动 (评论、点赞、收藏、分享)';
    RAISE NOTICE '  ✅ 留言赞助 (留言墙、赞助记录)';
    RAISE NOTICE '  ✅ 系统配置';
    RAISE NOTICE '=====================================================';
    RAISE NOTICE '安全特性:';
    RAISE NOTICE '  ✅ Row Level Security (RLS) 已启用';
    RAISE NOTICE '  ✅ UUID主键';
    RAISE NOTICE '  ✅ 自动时间戳';
    RAISE NOTICE '  ✅ 数据完整性约束';
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'PostGIS地理功能已启用';
    RAISE NOTICE '中文全文搜索已配置';
    RAISE NOTICE '=====================================================';
END $$;

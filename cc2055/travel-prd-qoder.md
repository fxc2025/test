# 旅行轨迹记录网站 - 产品需求文档 (PRD)

**版本**: v2.0  
**创建时间**: 2025年11月16日  
**技术栈**: Supabase + PostgreSQL + PostGIS  
**文档状态**: 技术方案确认阶段

---

## 1. 产品概述

### 1.1 产品定位
**个人旅行轨迹记录与分享平台** - 专注于个人旅行经历的系统化记录、数据可视化呈现和社交互动支持。

### 1.2 核心价值主张
- ✅ **轨迹可视化**：基于发布内容的定位信息生成个人旅行地图
- ✅ **内容管理**：长文章、短动态、专题的分类管理体系
- ✅ **社交互动**：点赞、评论、分享、收藏、赞助等完整功能
- ✅ **数据统计**：自动统计公里数、天数、城市数等核心指标

### 1.3 目标用户

| 用户类型 | 核心需求 | 使用场景 |
|---------|----------|----------|
| **旅行记录者** | 系统化记录轨迹，生成个人地图 | 发布文章、时光轴，管理照片 |
| **社交互动用户** | 浏览内容，互动交流 | 点赞评论，留言赞助 |
| **内容浏览者** | 浏览精美旅行内容 | 查看文章、照片、轨迹图 |

---

## 2. 核心业务逻辑

### 2.1 旅行轨迹生成机制

#### 轨迹点来源
通过**发布文章/时光轴/照片时的定位信息**生成

```
作者发布内容 → 填写定位信息 → 选择"是否在轨迹图显示" → 系统生成轨迹点 → 轨迹图展示
```

#### 业务规则
- 只有作者本人可创建轨迹点
- 轨迹点类型：文章(1)、时光轴(2)、照片(3)
- 轨迹点是静态的，基于发布时定位
- 通过 `show_on_track` 字段控制显示

#### 轨迹连线逻辑
| 旅行方式 | 连线颜色 |
|---------|---------|
| 驾车/自驾 | 红色 |
| 骑行 | 蓝色 |
| 徒步 | 绿色 |
| 火车/飞机 | 橙色 |

### 2.2 内容类型体系

#### 旅行文章
**必填**：标题、摘要、内容、分类、定位、旅行日期、旅行方式  
**选填**：封面、公里数、天气、心情、体重、推荐指数、标签、扩展字段

#### 专题文章
**必填**：专题名称、描述、关联文章  
**选填**：封面、标签

#### 时光轴
**必填**：内容（500字限制）  
**选填**：图片(1-9张)、定位、里程碑、心情标签、天气标签

#### 照片墙
**必填**：照片URL、分类（风景/美食/人物/文化/其他）  
**选填**：描述、定位、拍摄时间、标签

### 2.3 数据统计

| 统计项 | 计算规则 | 更新时机 |
|-------|---------|----------|
| 总公里数 | 文章公里数之和 | 文章发布/编辑时 |
| 总天数 | 最早到最晚旅行日期 | 文章发布/编辑时 |
| 途径城市数 | 不同地址城市去重 | 内容发布时 |
| 总获赞数 | 所有内容点赞数之和 | 点赞操作时 |
| 总评论数 | 所有内容评论数之和 | 评论操作时 |

---

## 3. 技术架构

### 3.1 系统架构
```
前端应用层 (Vue 3 + TypeScript)
    ↓
Supabase 服务层
    ├─ Auth (认证服务)
    ├─ Database (PostgreSQL + PostGIS)
    ├─ Storage (对象存储)
    ├─ Edge Functions (无服务器API)
    └─ Realtime (实时订阅)
    ↓
第三方服务层 (地图/支付/CDN)
```

### 3.2 技术栈

| 技术层 | 技术选型 |
|--------|----------|
| 前端框架 | Vue 3 + TypeScript |
| UI组件库 | Element Plus |
| 地图服务 | 高德地图 Web API |
| 后端服务 | Supabase |
| 数据库 | PostgreSQL 14+ + PostGIS |
| 文件存储 | Supabase Storage |
| 部署 | Vercel/Netlify |

---

## 4. 数据模型设计

### 4.1 设计原则

#### Supabase最佳实践
- 所有表使用UUID作为主键
- 使用TIMESTAMPTZ存储时间
- 启用Row Level Security (RLS)
- 使用触发器自动更新时间戳
- 外键约束确保数据完整性

#### 命名规范
- 表名：`m2_` 前缀 + snake_case
- 字段名：snake_case
- 索引名：`idx_<表名>_<字段名>`

### 4.2 核心数据表

#### 用户系统

**m2_users** - 用户基础信息
```sql
id UUID PRIMARY KEY,
username VARCHAR(50) UNIQUE NOT NULL,
email VARCHAR(100) UNIQUE,
nickname VARCHAR(50),
avatar VARCHAR(255),
is_author BOOLEAN DEFAULT FALSE,
status SMALLINT DEFAULT 1
```

**m2_user_travel_stats** - 用户旅行统计
```sql
user_id UUID UNIQUE,
total_distance DECIMAL(12,2),
total_days INTEGER,
cities_count INTEGER,
articles_count INTEGER,
total_likes_received INTEGER
```

**m2_user_follows** - 用户关注关系
```sql
follower_id UUID,
following_id UUID,
UNIQUE(follower_id, following_id)
```

#### 轨迹系统

**m2_track_points** - 轨迹点
```sql
user_id UUID,
latitude DECIMAL(10,8),
longitude DECIMAL(11,8),
point_type SMALLINT CHECK (1-3),
related_id UUID,
is_public BOOLEAN
```

**m2_track_segments** - 轨迹段
```sql
start_point_id UUID,
end_point_id UUID,
distance DECIMAL(10,2),
segment_order INTEGER
```

#### 内容管理

**m2_article_categories** - 文章分类
```sql
name VARCHAR(50) UNIQUE,
description TEXT,
display_order INTEGER
```

**m2_articles** - 旅行文章
```sql
user_id UUID,
category_id UUID,
title VARCHAR(200) NOT NULL,
content TEXT NOT NULL,
latitude DECIMAL(10,8),
longitude DECIMAL(11,8),
travel_distance DECIMAL(10,2),
tags TEXT[],
extension_fields JSONB,
status SMALLINT DEFAULT 1
```

**m2_special_topics** - 专题
```sql
user_id UUID,
title VARCHAR(200),
cover_image VARCHAR(255),
article_count INTEGER
```

**m2_timeline_posts** - 时光轴
```sql
user_id UUID,
content VARCHAR(500),
images JSONB,
milestone VARCHAR(100),
show_on_track BOOLEAN
```

**m2_photos** - 照片
```sql
user_id UUID,
file_url VARCHAR(255),
category VARCHAR(50),
tags TEXT[],
latitude DECIMAL(10,8),
longitude DECIMAL(11,8)
```

#### 社交互动

**m2_comments** - 评论
```sql
user_id UUID,
target_type SMALLINT,
target_id UUID,
parent_id UUID,
content TEXT NOT NULL
```

**m2_likes** - 点赞
```sql
user_id UUID,
target_type SMALLINT,
target_id UUID,
UNIQUE(user_id, target_type, target_id)
```

**m2_bookmarks** - 收藏
```sql
user_id UUID,
target_type SMALLINT,
target_id UUID
```

**m2_shares** - 分享
```sql
user_id UUID,
target_type SMALLINT,
target_id UUID,
share_platform VARCHAR(50)
```

#### 留言与赞助

**m2_messages** - 留言墙
```sql
user_id UUID,
author_id UUID,
content TEXT NOT NULL,
reply_content TEXT,
status SMALLINT
```

**m2_sponsorships** - 赞助记录
```sql
user_id UUID,
author_id UUID,
amount DECIMAL(10,2) CHECK (>0),
message TEXT,
is_anonymous BOOLEAN,
payment_status SMALLINT
```

#### 系统配置

**m2_system_configs** - 系统配置
```sql
config_key VARCHAR(100) UNIQUE,
config_value TEXT,
config_type VARCHAR(50),
is_public BOOLEAN
```

---

## 5. 页面功能设计

### 5.1 通用模块

**导航栏**：首页 - 旅行轨迹 - 时光轴 - 记忆留影 - 故事与酒 - 加油站 - 留言墙  
**页脚**：网站信息、导航、联系方式、版权

### 5.2 首页 (Home)

#### 页面结构
```
Hero区域（背景大图 + 作者信息 + Slogan）
    ↓
Stats区域（旅行数据概览）
    ↓
Aboutme区域（自我介绍）
    ↓
旅行初心区域（图文展示）
    ↓
时光留影区域（照片轮播）
    ↓
精选内容区（最新文章 + 时光轴）
    ↓
赞助者区域（赞助人轮播）
    ↓
合作伙伴区域（品牌轮播）
    ↓
CTA区域（赞助按钮）
```

### 5.3 轨迹图 (Track Map)

#### 布局
- 左侧：地图区域（轨迹点标记 + 连线）
- 右侧：轨迹点详情列表 + 统计信息

#### 功能
- 轨迹点标记（不同图标）
- 轨迹连线（不同颜色）
- 点击弹出详情卡片
- 统计信息显示

### 5.4 文章系统

#### 列表页
- 精选推荐（大图展示）
- 最新文章列表（封面 + 标题 + 摘要 + 互动数据）
- 分页/无限滚动
- 文章搜索和分类筛选

#### 详情页
- 左侧：文章内容 + 互动区 + 相关文章
- 右侧：搜索框 + 推荐文章 + 精选专题
- 距离显示："作者距离您 X 公里"

### 5.5 时光轴 (Timeline)

#### 结构
- 时光轴介绍（头像 + 统计）
- 发布框（仅作者可见）
- 动态列表（时间倒序）
- 互动功能（点赞/评论/分享）

### 5.6 照片墙 (Photo Wall)

#### 功能
- 分类标签（全部/风景/美食/人物/文化）
- 瀑布流布局（Masonry）
- 懒加载
- 大图预览

### 5.7 留言墙 (Message Wall)

#### 功能
- 留言列表（头像 + 内容 + 位置 + 作者回复）
- 我要留言（登录用户）
- 留言管理（作者）

### 5.8 加油站 (Sponsor Wall)

#### 功能
- 赞助者展示（头像 + 金额 + 留言 + 徽章）
- 赞助统计（总额 + 人数 + 月度统计）
- 赞助按钮（金额选择 + 留言 + 支付）

---

## 6. 用户认证与权限

### 6.1 Supabase Auth集成

#### 认证方式
- Email + Password 登录
- Email 验证
- 密码重置
- OAuth 社交登录（可选）

#### 认证流程
```sql
-- 用户注册
1. 用户填写注册信息
2. Supabase Auth创建用户
3. 发送验证邮件
4. 用户点击验证链接
5. 账户激活
6. 触发器自动创建m2_users记录

-- 用户登录
1. 用户输入凭证
2. Supabase Auth验证
3. 返回JWT Token
4. 前端存储Token
5. 请求携带Token

-- 密码重置
1. 用户请求重置
2. 发送重置邮件
3. 用户点击链接
4. 设置新密码
```

### 6.2 权限控制 (RLS)

#### 用户权限矩阵
| 操作 | 游客 | 登录用户 | 作者 |
|-----|------|----------|------|
| 浏览内容 | ✅ | ✅ | ✅ |
| 点赞评论 | ❌ | ✅ | ✅ |
| 收藏分享 | ❌ | ✅ | ✅ |
| 发布内容 | ❌ | ❌ | ✅ |
| 管理内容 | ❌ | ❌ | ✅ (自己的) |

#### RLS策略示例
```sql
-- 公开内容可查看
CREATE POLICY "Public content viewable" ON m2_articles
    FOR SELECT USING (status = 1);

-- 作者管理自己的内容
CREATE POLICY "Authors manage own content" ON m2_articles
    FOR ALL USING (auth.uid() = user_id);

-- 用户管理自己的点赞
CREATE POLICY "Users manage own likes" ON m2_likes
    FOR ALL USING (auth.uid() = user_id);
```

---

## 7. 性能优化策略

### 7.1 数据库优化

#### 索引策略
- B-Tree索引：主键、外键、常用查询字段
- GiST索引：地理坐标字段（PostGIS）
- GIN索引：数组字段、全文搜索
- 复合索引：多字段联合查询

#### 查询优化
- 使用视图简化复杂查询
- 避免N+1查询
- 使用连接查询代替子查询
- 合理使用LIMIT和OFFSET

### 7.2 前端优化

- 图片懒加载
- 虚拟滚动（大列表）
- 路由懒加载
- 资源压缩（Gzip/Brotli）
- CDN加速

### 7.3 缓存策略

- 热点数据Redis缓存
- 静态资源浏览器缓存
- API响应缓存
- 图片CDN缓存

---

## 8. 数据统计与分析

### 8.1 统计维度

#### 用户行为埋点
- 页面访问（PV/UV）
- 内容浏览时长
- 点赞/评论/分享行为
- 搜索关键词

#### 业务数据统计
- 用户注册数
- 内容发布数
- 互动数据
- 赞助金额

### 8.2 统计函数

```sql
-- 更新用户统计
CREATE FUNCTION update_user_stats(user_uuid UUID)
-- 计算旅行数据
-- 更新统计表
```

---

## 9. 隐私保护与合规

### 9.1 隐私保护

- 位置信息模糊化（精确到城市）
- 个人信息最小化收集
- 敏感数据加密存储
- 基于角色的访问控制

### 9.2 合规要求

- 用户协议和隐私政策
- 数据删除权（7天内处理）
- Cookie使用告知
- 未成年人保护

---

## 10. 开发计划与里程碑

### 10.1 开发阶段

| 阶段 | 时间 | 主要任务 |
|-----|------|----------|
| 需求设计 | 2周 | 需求确认、原型设计 |
| 技术架构 | 1周 | 技术选型、架构设计 |
| 基础开发 | 4周 | 用户系统、基础框架 |
| 核心功能 | 6周 | 内容发布、轨迹图 |
| 社交功能 | 3周 | 互动系统、评论点赞 |
| 页面开发 | 4周 | 所有页面UI和交互 |
| 测试优化 | 2周 | 功能测试、性能优化 |
| 上线部署 | 1周 | 环境配置、数据迁移 |

### 10.2 关键里程碑

| 里程碑 | 时间点 | 验收标准 |
|--------|--------|----------|
| MVP版本 | 第8周 | 用户注册、内容发布、基础浏览 |
| 核心功能完成 | 第14周 | 轨迹图、社交功能完善 |
| 测试完成 | 第16周 | 所有功能测试通过 |
| 正式上线 | 第17周 | 稳定运行，无重大BUG |

---

## 附录

### A. 数据库表清单

1. **用户系统**：m2_users, m2_user_sessions, m2_user_travel_stats, m2_user_follows
2. **轨迹系统**：m2_track_points, m2_track_segments
3. **内容管理**：m2_article_categories, m2_articles, m2_special_topics, m2_topic_article_relations, m2_timeline_posts, m2_photos, m2_timeline_photo_relations
4. **社交互动**：m2_comments, m2_likes, m2_bookmarks, m2_shares
5. **留言赞助**：m2_messages, m2_sponsorships
6. **系统配置**：m2_system_configs

### B. 核心API接口

#### 用户相关
- POST /api/auth/signup - 用户注册
- POST /api/auth/login - 用户登录
- POST /api/auth/logout - 用户登出
- GET /api/user/profile - 获取用户信息
- PUT /api/user/profile - 更新用户信息
- GET /api/user/stats - 获取用户统计

#### 文章相关
- GET /api/articles - 获取文章列表
- GET /api/articles/:id - 获取文章详情
- POST /api/articles - 创建文章
- PUT /api/articles/:id - 更新文章
- DELETE /api/articles/:id - 删除文章

#### 轨迹相关
- GET /api/tracks - 获取轨迹点列表
- GET /api/tracks/map - 获取轨迹地图数据

#### 互动相关
- POST /api/likes - 点赞
- DELETE /api/likes/:id - 取消点赞
- POST /api/comments - 发表评论
- GET /api/comments - 获取评论列表

### C. 技术文档链接

- Supabase官方文档: https://supabase.com/docs
- PostGIS文档: https://postgis.net/docs/
- Vue 3文档: https://vuejs.org/
- 高德地图API: https://lbs.amap.com/api/javascript-api/summary

---

**文档版本**: v2.0  
**最后更新**: 2025年11月16日  
**文档状态**: 技术方案确认阶段

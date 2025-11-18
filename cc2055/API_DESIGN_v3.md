# 旅行轨迹记录平台 - API 接口设计文档 v3.0

**版本**: v3.0  
**更新时间**: 2025-11-18  
**API 基础路径**: `/api/v1`  
**认证方式**: Bearer Token (JWT)  
**响应格式**: JSON

---

## 📋 目录

1. [API 设计规范](#1-api-设计规范)
2. [认证授权](#2-认证授权)
3. [用户模块](#3-用户模块)
4. [文章模块](#4-文章模块)
5. [专题模块](#5-专题模块)
6. [时光轴模块](#6-时光轴模块)
7. [照片模块](#7-照片模块)
8. [轨迹模块](#8-轨迹模块)
9. [互动模块](#9-互动模块)
10. [留言赞助模块](#10-留言赞助模块)
11. [文件上传模块](#11-文件上传模块)
12. [通知模块](#12-通知模块)
13. [系统模块](#13-系统模块)
14. [错误码定义](#14-错误码定义)
15. [Webhook 回调](#15-webhook-回调)

---

## 1. API 设计规范

### 1.1 请求规范

#### HTTP 方法语义

| 方法 | 用途 | 幂等性 |
|------|------|--------|
| GET | 获取资源 | ✅ |
| POST | 创建资源 | ❌ |
| PUT | 完整更新资源 | ✅ |
| PATCH | 部分更新资源 | ❌ |
| DELETE | 删除资源 | ✅ |

#### 请求头

```http
GET /api/v1/articles HTTP/1.1
Host: api.traveltracker.com
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json
X-Platform: web | miniapp | app
X-Client-Version: 1.0.0
X-Request-ID: uuid-v4
Accept-Language: zh-CN
```

#### 查询参数规范

```
GET /api/v1/articles?
  page=1                    # 页码（从 1 开始）
  &pageSize=20              # 每页数量
  &sort=published_at        # 排序字段
  &order=desc               # 排序方向（asc/desc）
  &category=uuid            # 分类筛选
  &tag=旅行                 # 标签筛选（支持多个）
  &keyword=关键词           # 搜索关键词
  &userId=uuid              # 用户筛选
  &status=1                 # 状态筛选
  &startDate=2025-01-01     # 开始日期
  &endDate=2025-12-31       # 结束日期
```

### 1.2 响应规范

#### 成功响应

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "title": "文章标题"
  },
  "message": "操作成功",
  "timestamp": "2025-11-18T10:30:00.000Z",
  "requestId": "uuid-v4"
}
```

#### 列表响应

```json
{
  "success": true,
  "data": {
    "items": [
      { "id": "uuid-1", "title": "文章1" },
      { "id": "uuid-2", "title": "文章2" }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 100,
      "totalPages": 5,
      "hasNextPage": true,
      "hasPrevPage": false
    }
  },
  "message": "查询成功",
  "timestamp": "2025-11-18T10:30:00.000Z"
}
```

#### 错误响应

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "参数验证失败",
    "details": {
      "title": "标题不能为空",
      "content": "内容长度必须大于 10 字符"
    },
    "path": "/api/v1/articles",
    "timestamp": "2025-11-18T10:30:00.000Z"
  },
  "requestId": "uuid-v4"
}
```

### 1.3 状态码规范

| 状态码 | 说明 | 场景 |
|--------|------|------|
| 200 | OK | 成功 |
| 201 | Created | 创建成功 |
| 204 | No Content | 删除成功 |
| 400 | Bad Request | 请求参数错误 |
| 401 | Unauthorized | 未认证 |
| 403 | Forbidden | 无权限 |
| 404 | Not Found | 资源不存在 |
| 409 | Conflict | 资源冲突 |
| 422 | Unprocessable Entity | 数据验证失败 |
| 429 | Too Many Requests | 请求频率限制 |
| 500 | Internal Server Error | 服务器错误 |
| 503 | Service Unavailable | 服务不可用 |

---

## 2. 认证授权

### 2.1 用户注册

```http
POST /api/v1/auth/signup
Content-Type: application/json
```

**请求体**：

```json
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "username": "traveler_john",
  "displayName": "John Traveler",
  "captcha": "验证码"
}
```

**响应**：

```json
{
  "success": true,
  "data": {
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "username": "traveler_john",
      "displayName": "John Traveler",
      "emailVerified": false
    },
    "message": "注册成功，请查收验证邮件"
  }
}
```

### 2.2 用户登录

```http
POST /api/v1/auth/login
Content-Type: application/json
```

**请求体**：

```json
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}
```

**响应**：

```json
{
  "success": true,
  "data": {
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "username": "traveler_john",
      "displayName": "John Traveler",
      "role": "user",
      "isAuthor": false
    },
    "session": {
      "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refreshToken": "refresh_token_here",
      "expiresIn": 3600,
      "expiresAt": "2025-11-18T11:30:00.000Z"
    }
  }
}
```

### 2.3 刷新 Token

```http
POST /api/v1/auth/refresh
Content-Type: application/json
```

**请求体**：

```json
{
  "refreshToken": "refresh_token_here"
}
```

### 2.4 登出

```http
POST /api/v1/auth/logout
Authorization: Bearer {accessToken}
```

### 2.5 重置密码

```http
POST /api/v1/auth/reset-password
Content-Type: application/json
```

**请求体**：

```json
{
  "email": "user@example.com"
}
```

### 2.6 修改密码

```http
POST /api/v1/auth/change-password
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "oldPassword": "OldPass123!",
  "newPassword": "NewPass456!"
}
```

---

## 3. 用户模块

### 3.1 获取当前用户信息

```http
GET /api/v1/users/me
Authorization: Bearer {accessToken}
```

**响应**：

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "username": "traveler_john",
    "displayName": "John Traveler",
    "email": "user@example.com",
    "avatarUrl": "https://cdn.example.com/avatars/uuid.jpg",
    "role": "author",
    "isAuthor": true,
    "profile": {
      "bio": "热爱旅行的自由职业者",
      "headline": "用脚步丈量世界",
      "location": "上海",
      "websiteUrl": "https://blog.example.com",
      "socialLinks": {
        "wechat": "wxid_xxx",
        "weibo": "@traveler_john"
      }
    },
    "stats": {
      "totalDistance": 12345.67,
      "totalDays": 365,
      "citiesCount": 50,
      "articlesCount": 120,
      "followersCount": 1234
    },
    "createdAt": "2024-01-01T00:00:00.000Z"
  }
}
```

### 3.2 更新当前用户信息

```http
PUT /api/v1/users/me
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "displayName": "New Display Name",
  "avatarUrl": "https://cdn.example.com/avatars/new.jpg",
  "profile": {
    "bio": "更新后的个人简介",
    "headline": "新的座右铭",
    "location": "北京",
    "websiteUrl": "https://newblog.example.com",
    "socialLinks": {
      "wechat": "new_wxid",
      "weibo": "@new_weibo"
    }
  }
}
```

### 3.3 获取用户公开信息

```http
GET /api/v1/users/:userId
```

**响应**：

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "username": "traveler_john",
    "displayName": "John Traveler",
    "avatarUrl": "https://cdn.example.com/avatars/uuid.jpg",
    "isAuthor": true,
    "profile": {
      "bio": "热爱旅行的自由职业者",
      "headline": "用脚步丈量世界",
      "location": "上海"
    },
    "stats": {
      "totalDistance": 12345.67,
      "totalDays": 365,
      "citiesCount": 50,
      "articlesCount": 120,
      "followersCount": 1234,
      "followingCount": 567
    },
    "isFollowing": false,
    "createdAt": "2024-01-01T00:00:00.000Z"
  }
}
```

### 3.4 关注用户

```http
POST /api/v1/users/:userId/follow
Authorization: Bearer {accessToken}
```

### 3.5 取消关注

```http
DELETE /api/v1/users/:userId/follow
Authorization: Bearer {accessToken}
```

### 3.6 获取粉丝列表

```http
GET /api/v1/users/:userId/followers?page=1&pageSize=20
```

### 3.7 获取关注列表

```http
GET /api/v1/users/:userId/following?page=1&pageSize=20
```

---

## 4. 文章模块

### 4.1 获取文章列表

```http
GET /api/v1/articles?page=1&pageSize=20&sort=published_at&order=desc
```

**查询参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| page | integer | 否 | 页码，默认 1 |
| pageSize | integer | 否 | 每页数量，默认 20，最大 100 |
| sort | string | 否 | 排序字段：published_at, view_count, like_count |
| order | string | 否 | 排序方向：asc, desc，默认 desc |
| category | uuid | 否 | 分类 ID |
| tag | string | 否 | 标签（可多个） |
| keyword | string | 否 | 搜索关键词 |
| userId | uuid | 否 | 作者 ID |
| startDate | date | 否 | 开始日期 (travel_date) |
| endDate | date | 否 | 结束日期 (travel_date) |

**响应**：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "title": "骑行川藏线：21 天的自由与孤独",
        "summary": "从成都到拉萨，2100公里的骑行之旅...",
        "coverImage": "https://cdn.example.com/covers/uuid.jpg",
        "author": {
          "id": "uuid",
          "username": "traveler_john",
          "displayName": "John Traveler",
          "avatarUrl": "https://cdn.example.com/avatars/uuid.jpg"
        },
        "category": {
          "id": "uuid",
          "name": "旅行日记"
        },
        "travelDate": "2024-05-01",
        "travelMethod": "骑行",
        "travelDistance": 2100.0,
        "location": {
          "city": "拉萨",
          "province": "西藏",
          "country": "中国"
        },
        "tags": ["骑行", "川藏线", "西藏"],
        "stats": {
          "viewCount": 12345,
          "likeCount": 567,
          "commentCount": 89,
          "bookmarkCount": 123
        },
        "publishedAt": "2024-06-01T10:30:00.000Z"
      }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 100,
      "totalPages": 5
    }
  }
}
```

### 4.2 获取文章详情

```http
GET /api/v1/articles/:id
```

**响应**：

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "title": "骑行川藏线：21 天的自由与孤独",
    "summary": "从成都到拉萨，2100公里的骑行之旅...",
    "content": "## 第一天：成都出发\n\n清晨的成都...",
    "coverImage": "https://cdn.example.com/covers/uuid.jpg",
    "author": {
      "id": "uuid",
      "username": "traveler_john",
      "displayName": "John Traveler",
      "avatarUrl": "https://cdn.example.com/avatars/uuid.jpg",
      "isAuthor": true
    },
    "category": {
      "id": "uuid",
      "name": "旅行日记"
    },
    "travelDate": "2024-05-01",
    "travelMethod": "骑行",
    "travelDistance": 2100.0,
    "location": {
      "latitude": 29.649869,
      "longitude": 91.117212,
      "address": "拉萨市城关区",
      "city": "拉萨",
      "province": "西藏",
      "country": "中国"
    },
    "tags": ["骑行", "川藏线", "西藏"],
    "mood": {
      "score": 5,
      "weather": "晴朗",
      "temperature": 18.5
    },
    "recommendation": {
      "rating": 5
    },
    "stats": {
      "viewCount": 12345,
      "likeCount": 567,
      "commentCount": 89,
      "shareCount": 45,
      "bookmarkCount": 123
    },
    "interactions": {
      "isLiked": false,
      "isBookmarked": false
    },
    "relatedArticles": [
      {
        "id": "uuid-2",
        "title": "相关文章标题",
        "coverImage": "url"
      }
    ],
    "createdAt": "2024-06-01T09:00:00.000Z",
    "updatedAt": "2024-06-01T10:00:00.000Z",
    "publishedAt": "2024-06-01T10:30:00.000Z"
  }
}
```

### 4.3 创建文章

```http
POST /api/v1/articles
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "title": "骑行川藏线：21 天的自由与孤独",
  "summary": "从成都到拉萨，2100公里的骑行之旅...",
  "content": "## 第一天：成都出发\n\n清晨的成都...",
  "coverImage": "https://cdn.example.com/covers/uuid.jpg",
  "categoryId": "uuid",
  "travelDate": "2024-05-01",
  "travelMethod": "骑行",
  "travelDistance": 2100.0,
  "location": {
    "latitude": 29.649869,
    "longitude": 91.117212,
    "address": "拉萨市城关区",
    "city": "拉萨",
    "province": "西藏",
    "country": "中国"
  },
  "showOnTrack": true,
  "tags": ["骑行", "川藏线", "西藏"],
  "mood": {
    "score": 5,
    "weather": "晴朗",
    "temperature": 18.5
  },
  "recommendation": {
    "rating": 5
  },
  "status": 0
}
```

**字段说明**：

- `status`: 0-草稿, 1-发布
- `showOnTrack`: 是否在轨迹图显示

**响应**：

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "title": "骑行川藏线：21 天的自由与孤独",
    "status": 0,
    "createdAt": "2024-06-01T09:00:00.000Z"
  },
  "message": "文章创建成功"
}
```

### 4.4 更新文章

```http
PUT /api/v1/articles/:id
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：同创建文章

### 4.5 删除文章

```http
DELETE /api/v1/articles/:id
Authorization: Bearer {accessToken}
```

### 4.6 发布文章

```http
POST /api/v1/articles/:id/publish
Authorization: Bearer {accessToken}
```

**响应**：

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "status": 1,
    "publishedAt": "2024-06-01T10:30:00.000Z"
  },
  "message": "文章发布成功"
}
```

### 4.7 搜索文章

```http
GET /api/v1/articles/search?q=川藏线&page=1&pageSize=20
```

### 4.8 获取推荐文章

```http
GET /api/v1/articles/recommended?limit=10
```

### 4.9 获取热门文章

```http
GET /api/v1/articles/trending?days=7&limit=10
```

### 4.10 获取文章分类

```http
GET /api/v1/articles/categories
```

**响应**：

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "name": "旅行日记",
      "description": "详细记录旅途见闻",
      "displayOrder": 1,
      "articlesCount": 120
    }
  ]
}
```

---

## 5. 专题模块

### 5.1 获取专题列表

```http
GET /api/v1/topics?page=1&pageSize=20
```

### 5.2 获取专题详情

```http
GET /api/v1/topics/:id
```

**响应**：

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "title": "我的西藏之旅",
    "description": "2024年西藏行系列文章",
    "coverImage": "https://cdn.example.com/covers/topic-uuid.jpg",
    "author": {
      "id": "uuid",
      "username": "traveler_john",
      "displayName": "John Traveler"
    },
    "tags": ["西藏", "骑行"],
    "articlesCount": 15,
    "articles": [
      {
        "id": "uuid-1",
        "title": "第一篇文章",
        "displayOrder": 1
      }
    ],
    "createdAt": "2024-06-01T00:00:00.000Z",
    "updatedAt": "2024-08-15T10:30:00.000Z"
  }
}
```

### 5.3 创建专题

```http
POST /api/v1/topics
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "title": "我的西藏之旅",
  "description": "2024年西藏行系列文章",
  "coverImage": "https://cdn.example.com/covers/topic.jpg",
  "tags": ["西藏", "骑行"],
  "articleIds": ["uuid-1", "uuid-2"],
  "status": 1
}
```

### 5.4 更新专题

```http
PUT /api/v1/topics/:id
Authorization: Bearer {accessToken}
```

### 5.5 删除专题

```http
DELETE /api/v1/topics/:id
Authorization: Bearer {accessToken}
```

### 5.6 专题关联文章

```http
POST /api/v1/topics/:id/articles
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "articleId": "uuid",
  "displayOrder": 3
}
```

### 5.7 专题移除文章

```http
DELETE /api/v1/topics/:id/articles/:articleId
Authorization: Bearer {accessToken}
```

---

## 6. 时光轴模块

### 6.1 获取时光轴列表

```http
GET /api/v1/timeline?page=1&pageSize=20&userId=uuid
```

**响应**：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "author": {
          "id": "uuid",
          "username": "traveler_john",
          "displayName": "John Traveler",
          "avatarUrl": "url"
        },
        "content": "今天骑行到了理塘，海拔4000米，呼吸有点困难但风景绝美！",
        "images": [
          {
            "url": "https://cdn.example.com/timeline/img1.jpg",
            "thumbnail": "https://cdn.example.com/timeline/thumb1.jpg"
          }
        ],
        "location": {
          "address": "四川省甘孜州理塘县",
          "latitude": 30.0,
          "longitude": 100.0
        },
        "milestone": "到达理塘",
        "mood": "兴奋",
        "weather": "晴朗",
        "stats": {
          "likeCount": 45,
          "commentCount": 12
        },
        "interactions": {
          "isLiked": false
        },
        "createdAt": "2024-05-05T14:30:00.000Z"
      }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 50
    }
  }
}
```

### 6.2 获取时光轴详情

```http
GET /api/v1/timeline/:id
```

### 6.3 发布时光轴

```http
POST /api/v1/timeline
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "content": "今天骑行到了理塘，海拔4000米，呼吸有点困难但风景绝美！",
  "images": [
    {
      "url": "https://cdn.example.com/timeline/img1.jpg",
      "thumbnail": "https://cdn.example.com/timeline/thumb1.jpg",
      "width": 1920,
      "height": 1080
    }
  ],
  "location": {
    "latitude": 30.0,
    "longitude": 100.0,
    "address": "四川省甘孜州理塘县"
  },
  "showOnTrack": true,
  "milestone": "到达理塘",
  "moodTag": "兴奋",
  "weatherTag": "晴朗",
  "relatedArticleId": "uuid"
}
```

### 6.4 更新时光轴

```http
PUT /api/v1/timeline/:id
Authorization: Bearer {accessToken}
```

### 6.5 删除时光轴

```http
DELETE /api/v1/timeline/:id
Authorization: Bearer {accessToken}
```

---

## 7. 照片模块

### 7.1 获取照片列表

```http
GET /api/v1/photos?page=1&pageSize=20&category=风景&userId=uuid
```

**查询参数**：

- `category`: 风景, 美食, 人物, 文化, 其他
- `tag`: 标签筛选
- `hasLocation`: true/false 是否有地理位置

**响应**：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "fileUrl": "https://cdn.example.com/photos/uuid.jpg",
        "thumbnailUrl": "https://cdn.example.com/photos/thumb_uuid.jpg",
        "width": 1920,
        "height": 1080,
        "description": "布达拉宫日落",
        "author": {
          "id": "uuid",
          "username": "traveler_john"
        },
        "category": "风景",
        "tags": ["西藏", "布达拉宫", "日落"],
        "location": {
          "address": "拉萨市城关区",
          "latitude": 29.657778,
          "longitude": 91.117212
        },
        "shootDate": "2024-05-21T18:30:00.000Z",
        "stats": {
          "likeCount": 234,
          "commentCount": 23
        },
        "createdAt": "2024-05-22T10:00:00.000Z"
      }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 200
    }
  }
}
```

### 7.2 获取照片详情

```http
GET /api/v1/photos/:id
```

### 7.3 上传照片

```http
POST /api/v1/photos
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "fileUrl": "https://cdn.example.com/photos/uuid.jpg",
  "thumbnailUrl": "https://cdn.example.com/photos/thumb_uuid.jpg",
  "width": 1920,
  "height": 1080,
  "sizeBytes": 2048000,
  "description": "布达拉宫日落",
  "category": "风景",
  "tags": ["西藏", "布达拉宫", "日落"],
  "location": {
    "latitude": 29.657778,
    "longitude": 91.117212,
    "address": "拉萨市城关区"
  },
  "shootDate": "2024-05-21T18:30:00.000Z",
  "showOnTrack": true
}
```

### 7.4 更新照片信息

```http
PUT /api/v1/photos/:id
Authorization: Bearer {accessToken}
```

### 7.5 删除照片

```http
DELETE /api/v1/photos/:id
Authorization: Bearer {accessToken}
```

### 7.6 批量上传照片

```http
POST /api/v1/photos/batch
Authorization: Bearer {accessToken}
Content-Type: application/json
```

---

## 8. 轨迹模块

### 8.1 获取用户轨迹点

```http
GET /api/v1/tracks/:userId/points?startDate=2024-01-01&endDate=2024-12-31
```

**响应**：

```json
{
  "success": true,
  "data": {
    "points": [
      {
        "id": "uuid",
        "location": {
          "latitude": 30.572269,
          "longitude": 104.066541,
          "address": "成都市武侯区"
        },
        "pointType": 1,
        "relatedId": "article-uuid",
        "title": "成都出发",
        "icon": "article",
        "color": "#E74C3C",
        "pointTime": "2024-05-01T08:00:00.000Z"
      }
    ],
    "stats": {
      "totalPoints": 50,
      "totalDistance": 2100.0,
      "totalDays": 21
    }
  }
}
```

### 8.2 获取轨迹地图数据

```http
GET /api/v1/tracks/:userId/map
```

**响应**：

```json
{
  "success": true,
  "data": {
    "points": [
      {
        "id": "uuid",
        "latitude": 30.572269,
        "longitude": 104.066541,
        "title": "成都出发",
        "type": 1,
        "icon": "article",
        "color": "#E74C3C",
        "time": "2024-05-01T08:00:00.000Z"
      }
    ],
    "segments": [
      {
        "id": "uuid",
        "start": [104.066541, 30.572269],
        "end": [102.285887, 30.046298],
        "travelMethod": "骑行",
        "color": "#3498DB",
        "distance": 180.5
      }
    ],
    "bounds": {
      "north": 31.0,
      "south": 29.0,
      "east": 105.0,
      "west": 102.0
    }
  }
}
```

### 8.3 获取轨迹段列表

```http
GET /api/v1/tracks/:userId/segments
```

### 8.4 创建轨迹段

```http
POST /api/v1/tracks/:userId/segments
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "startPointId": "uuid-1",
  "endPointId": "uuid-2",
  "travelMethod": "骑行",
  "distanceKm": 180.5,
  "durationMinutes": 540
}
```

### 8.5 获取轨迹统计

```http
GET /api/v1/tracks/:userId/stats
```

**响应**：

```json
{
  "success": true,
  "data": {
    "totalDistance": 12345.67,
    "totalDays": 365,
    "citiesCount": 50,
    "pointsCount": 150,
    "travelMethods": {
      "骑行": 2100.0,
      "徒步": 500.0,
      "自驾": 8000.0
    },
    "monthlyStats": [
      {
        "month": "2024-05",
        "distance": 2100.0,
        "days": 21
      }
    ]
  }
}
```

---

## 9. 互动模块

### 9.1 点赞

```http
POST /api/v1/likes
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "targetType": 1,
  "targetId": "uuid"
}
```

**targetType**：1-文章, 2-时光轴, 3-评论, 4-照片

### 9.2 取消点赞

```http
DELETE /api/v1/likes
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "targetType": 1,
  "targetId": "uuid"
}
```

### 9.3 评论

```http
POST /api/v1/comments
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "targetType": 1,
  "targetId": "uuid",
  "content": "写得太好了！",
  "parentId": "uuid"
}
```

### 9.4 获取评论列表

```http
GET /api/v1/comments?targetType=1&targetId=uuid&page=1&pageSize=20
```

**响应**：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "author": {
          "id": "uuid",
          "username": "reader_alice",
          "displayName": "Alice",
          "avatarUrl": "url"
        },
        "content": "写得太好了！",
        "likeCount": 12,
        "replyCount": 3,
        "isLiked": false,
        "createdAt": "2024-06-02T14:30:00.000Z",
        "replies": [
          {
            "id": "uuid-reply",
            "author": { ... },
            "content": "谢谢！",
            "createdAt": "2024-06-02T15:00:00.000Z"
          }
        ]
      }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 89
    }
  }
}
```

### 9.5 删除评论

```http
DELETE /api/v1/comments/:id
Authorization: Bearer {accessToken}
```

### 9.6 收藏

```http
POST /api/v1/bookmarks
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "targetType": 1,
  "targetId": "uuid"
}
```

### 9.7 取消收藏

```http
DELETE /api/v1/bookmarks
Authorization: Bearer {accessToken}
Content-Type: application/json
```

### 9.8 获取我的收藏

```http
GET /api/v1/bookmarks?page=1&pageSize=20&targetType=1
```

### 9.9 分享记录

```http
POST /api/v1/shares
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "targetType": 1,
  "targetId": "uuid",
  "platform": "wechat"
}
```

---

## 10. 留言赞助模块

### 10.1 获取留言列表

```http
GET /api/v1/messages?authorId=uuid&page=1&pageSize=20
```

### 10.2 发送留言

```http
POST /api/v1/messages
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "authorId": "uuid",
  "content": "你的文章写得太棒了！",
  "isPublic": true
}
```

### 10.3 回复留言

```http
PUT /api/v1/messages/:id/reply
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "replyContent": "谢谢支持！"
}
```

### 10.4 删除留言

```http
DELETE /api/v1/messages/:id
Authorization: Bearer {accessToken}
```

### 10.5 获取赞助列表

```http
GET /api/v1/sponsorships?authorId=uuid&page=1&pageSize=20
```

### 10.6 创建赞助订单

```http
POST /api/v1/sponsorships
Authorization: Bearer {accessToken}
Content-Type: application/json
```

**请求体**：

```json
{
  "authorId": "uuid",
  "amount": 50.00,
  "message": "支持你继续创作！",
  "isAnonymous": false,
  "paymentChannel": "wechat"
}
```

**响应**：

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "amount": 50.00,
    "paymentStatus": "pending",
    "paymentData": {
      "wechatPayParams": {
        "appId": "wx...",
        "timeStamp": "...",
        "nonceStr": "...",
        "package": "...",
        "signType": "RSA",
        "paySign": "..."
      }
    },
    "createdAt": "2024-06-02T10:00:00.000Z"
  }
}
```

### 10.7 查询支付状态

```http
GET /api/v1/sponsorships/:id/status
Authorization: Bearer {accessToken}
```

### 10.8 获取赞助统计

```http
GET /api/v1/sponsorships/stats?authorId=uuid
```

**响应**：

```json
{
  "success": true,
  "data": {
    "totalAmount": 12345.00,
    "totalCount": 234,
    "monthlyAmount": 1200.00,
    "topSponsors": [
      {
        "user": {
          "displayName": "Alice",
          "avatarUrl": "url"
        },
        "totalAmount": 500.00,
        "count": 5
      }
    ]
  }
}
```

---

## 11. 文件上传模块

### 11.1 上传图片

```http
POST /api/v1/upload/image
Authorization: Bearer {accessToken}
Content-Type: multipart/form-data
```

**请求体**：

```
file: (binary)
folder: articles | timeline | photos | avatars
```

**响应**：

```json
{
  "success": true,
  "data": {
    "url": "https://cdn.example.com/uploads/uuid.jpg",
    "thumbnail": "https://cdn.example.com/uploads/thumb_uuid.jpg",
    "width": 1920,
    "height": 1080,
    "size": 2048000,
    "format": "jpeg"
  }
}
```

### 11.2 批量上传图片

```http
POST /api/v1/upload/images
Authorization: Bearer {accessToken}
Content-Type: multipart/form-data
```

**请求体**：

```
files[]: (binary array)
folder: timeline | photos
```

### 11.3 获取签名 URL

```http
GET /api/v1/upload/signed-url?filename=image.jpg&folder=articles
Authorization: Bearer {accessToken}
```

**响应**：

```json
{
  "success": true,
  "data": {
    "uploadUrl": "https://storage.example.com/upload?signature=...",
    "publicUrl": "https://cdn.example.com/uploads/uuid.jpg",
    "expiresAt": "2024-06-02T11:00:00.000Z"
  }
}
```

### 11.4 删除文件

```http
DELETE /api/v1/upload/:fileId
Authorization: Bearer {accessToken}
```

---

## 12. 通知模块

### 12.1 获取通知列表

```http
GET /api/v1/notifications?page=1&pageSize=20&type=comment&status=unread
```

**查询参数**：

- `type`: system, comment, like, follow, sponsorship, message, article
- `status`: unread, read

**响应**：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "type": "comment",
        "title": "新评论通知",
        "content": "用户 Alice 评论了你的文章《骑行川藏线》",
        "metadata": {
          "userId": "uuid",
          "articleId": "uuid",
          "commentId": "uuid"
        },
        "status": "unread",
        "createdAt": "2024-06-02T14:30:00.000Z"
      }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 45
    }
  }
}
```

### 12.2 获取未读数量

```http
GET /api/v1/notifications/unread-count
Authorization: Bearer {accessToken}
```

**响应**：

```json
{
  "success": true,
  "data": {
    "total": 45,
    "byType": {
      "comment": 12,
      "like": 23,
      "follow": 5,
      "sponsorship": 3,
      "message": 2
    }
  }
}
```

### 12.3 标记已读

```http
PUT /api/v1/notifications/:id/read
Authorization: Bearer {accessToken}
```

### 12.4 全部标记已读

```http
PUT /api/v1/notifications/read-all
Authorization: Bearer {accessToken}
```

### 12.5 删除通知

```http
DELETE /api/v1/notifications/:id
Authorization: Bearer {accessToken}
```

---

## 13. 系统模块

### 13.1 获取系统配置

```http
GET /api/v1/system/config
```

**响应**：

```json
{
  "success": true,
  "data": {
    "site": {
      "title": "旅行轨迹记录平台",
      "description": "记录旅途，分享精彩瞬间",
      "language": "zh-CN"
    },
    "map": {
      "defaultZoom": 4,
      "defaultCenter": [104.066541, 30.572269]
    },
    "features": {
      "sponsorshipEnabled": true,
      "commentEnabled": true
    }
  }
}
```

### 13.2 搜索

```http
GET /api/v1/system/search?q=川藏线&type=article&page=1&pageSize=20
```

**查询参数**：

- `q`: 搜索关键词
- `type`: article, user, timeline, photo (可多选)

### 13.3 统计信息

```http
GET /api/v1/system/stats
```

**响应**：

```json
{
  "success": true,
  "data": {
    "totalUsers": 12345,
    "totalArticles": 5678,
    "totalDistance": 1234567.89,
    "totalCities": 500
  }
}
```

---

## 14. 错误码定义

| 错误码 | HTTP 状态 | 说明 | 解决方案 |
|--------|-----------|------|----------|
| `SUCCESS` | 200 | 成功 | - |
| `BAD_REQUEST` | 400 | 请求参数错误 | 检查请求参数 |
| `UNAUTHORIZED` | 401 | 未授权 | 登录后重试 |
| `FORBIDDEN` | 403 | 无权限 | 联系管理员 |
| `NOT_FOUND` | 404 | 资源不存在 | 检查资源 ID |
| `CONFLICT` | 409 | 资源冲突 | 检查唯一性约束 |
| `VALIDATION_ERROR` | 422 | 数据验证失败 | 检查字段格式 |
| `RATE_LIMIT` | 429 | 请求频率限制 | 稍后重试 |
| `SERVER_ERROR` | 500 | 服务器错误 | 联系技术支持 |
| `AUTH_INVALID_TOKEN` | 401 | Token 无效 | 重新登录 |
| `AUTH_TOKEN_EXPIRED` | 401 | Token 过期 | 刷新 Token |
| `USER_NOT_FOUND` | 404 | 用户不存在 | 检查用户 ID |
| `ARTICLE_NOT_FOUND` | 404 | 文章不存在 | 检查文章 ID |
| `PERMISSION_DENIED` | 403 | 权限不足 | 检查用户权限 |
| `FILE_TOO_LARGE` | 413 | 文件过大 | 压缩文件后上传 |
| `INVALID_FILE_TYPE` | 422 | 文件类型不支持 | 使用支持的格式 |

---

## 15. Webhook 回调

### 15.1 支付回调

```http
POST /api/v1/webhooks/payment/wechat
Content-Type: application/json
```

**请求体**：

```json
{
  "id": "webhook-id",
  "create_time": "2024-06-02T10:30:00+08:00",
  "event_type": "TRANSACTION.SUCCESS",
  "resource": {
    "algorithm": "AEAD_AES_256_GCM",
    "ciphertext": "...",
    "nonce": "...",
    "associated_data": "..."
  }
}
```

**响应**：

```json
{
  "code": "SUCCESS",
  "message": "处理成功"
}
```

---

## 附录

### A. 频率限制

| 用户类型 | 限制 |
|---------|------|
| 匿名用户 | 10 req/min |
| 普通用户 | 100 req/min |
| 作者 | 200 req/min |
| 管理员 | 1000 req/min |

### B. 数据限制

| 字段 | 限制 |
|------|------|
| 文章标题 | 200 字符 |
| 文章摘要 | 500 字符 |
| 文章正文 | 100,000 字符 |
| 时光轴内容 | 500 字符 |
| 评论内容 | 1000 字符 |
| 图片大小 | 10 MB |
| 批量上传 | 最多 9 张 |

### C. SDK 示例

#### JavaScript/TypeScript

```typescript
import axios from 'axios';

const api = axios.create({
  baseURL: 'https://api.traveltracker.com/api/v1',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
    'X-Platform': 'web'
  }
});

// 拦截器：自动添加 Token
api.interceptors.request.use(config => {
  const token = localStorage.getItem('access_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// 使用示例
const getArticles = async (params) => {
  const response = await api.get('/articles', { params });
  return response.data;
};
```

---

**文档版本**: v3.0  
**最后更新**: 2025-11-18  
**维护者**: 开发团队

---

© 2025 旅行轨迹记录平台 API 文档

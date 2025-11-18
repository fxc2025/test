# API 接口文档

本项目采用前后端分离架构，所有业务逻辑通过统一的 RESTful API 接口实现，方便后续扩展到小程序、APP 等多端应用。

## 通用说明

### 请求格式

- **Content-Type**: `application/json`
- **方法**: GET, POST, PUT, DELETE
- **认证**: 基于 Cookie 的会话认证（由 Supabase 自动处理）

### 响应格式

所有接口统一返回以下格式：

```typescript
{
  success: boolean      // 请求是否成功
  data?: any           // 成功时返回的数据
  error?: string       // 失败时的错误信息
  message?: string     // 额外的提示信息
}
```

### HTTP 状态码

- `200` - 请求成功
- `201` - 创建成功
- `400` - 请求参数错误
- `401` - 未授权（未登录）
- `403` - 禁止访问（权限不足）
- `404` - 资源不存在
- `500` - 服务器内部错误

---

## 认证接口

### 1. 用户注册

注册新用户账号。

**接口**: `POST /api/auth/register`

**请求参数**:

```json
{
  "email": "user@example.com",
  "password": "password123",
  "role": "user"  // 可选: "user" | "author"，默认为 "user"
}
```

**成功响应** (201):

```json
{
  "success": true,
  "message": "注册成功！请检查您的邮箱以验证账号。",
  "data": {
    "userId": "uuid-string"
  }
}
```

**失败响应** (400):

```json
{
  "success": false,
  "error": "邮箱已被注册"
}
```

**使用示例**:

```javascript
const response = await fetch('/api/auth/register', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: 'user@example.com',
    password: 'password123',
    role: 'user'
  })
})

const data = await response.json()
if (data.success) {
  // 注册成功，跳转到邮箱验证页面
  router.push('/verify-email?email=' + encodeURIComponent(email))
}
```

---

### 2. 用户登录

使用邮箱和密码登录。

**接口**: `POST /api/auth/login`

**请求参数**:

```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**成功响应** (200):

```json
{
  "success": true,
  "message": "登录成功",
  "data": {
    "user": {
      "id": "uuid-string",
      "email": "user@example.com",
      "created_at": "2024-01-01T00:00:00Z"
    },
    "redirectTo": "/profile"  // 或 "/dashboard" (作者)
  }
}
```

**失败响应** (401):

```json
{
  "success": false,
  "error": "邮箱或密码错误"
}
```

**使用示例**:

```javascript
const response = await fetch('/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: 'user@example.com',
    password: 'password123'
  })
})

const data = await response.json()
if (data.success) {
  // 登录成功，跳转到对应页面
  router.push(data.data.redirectTo)
}
```

---

### 3. 退出登录

退出当前登录账号。

**接口**: `POST /api/auth/logout`

**请求参数**: 无

**成功响应** (200):

```json
{
  "success": true,
  "message": "退出登录成功"
}
```

**使用示例**:

```javascript
const response = await fetch('/api/auth/logout', {
  method: 'POST'
})

const data = await response.json()
if (data.success) {
  router.push('/login')
}
```

---

## 用户接口

### 1. 获取用户信息

获取当前登录用户的详细信息。

**接口**: `GET /api/user/profile`

**请求参数**: 无

**成功响应** (200):

```json
{
  "success": true,
  "data": {
    "user": {
      "id": "uuid-string",
      "email": "user@example.com",
      "created_at": "2024-01-01T00:00:00Z",
      "email_confirmed_at": "2024-01-01T00:10:00Z"
    },
    "profile": {
      "id": "uuid-string",
      "user_id": "uuid-string",
      "role": "user",
      "full_name": "张三",
      "avatar_url": "https://...",
      "bio": "个人简介",
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:00:00Z"
    }
  }
}
```

**失败响应** (401):

```json
{
  "success": false,
  "error": "未授权"
}
```

**使用示例**:

```javascript
const response = await fetch('/api/user/profile')
const data = await response.json()

if (data.success) {
  const { user, profile } = data.data
  console.log('用户信息:', user)
  console.log('个人资料:', profile)
}
```

---

### 2. 更新用户信息

更新当前登录用户的个人资料。

**接口**: `PUT /api/user/profile`

**请求参数**:

```json
{
  "full_name": "张三",
  "bio": "这是我的个人简介",
  "avatar_url": "https://example.com/avatar.jpg"
}
```

**成功响应** (200):

```json
{
  "success": true,
  "message": "更新成功",
  "data": {
    "id": "uuid-string",
    "user_id": "uuid-string",
    "role": "user",
    "full_name": "张三",
    "bio": "这是我的个人简介",
    "avatar_url": "https://example.com/avatar.jpg",
    "updated_at": "2024-01-01T12:00:00Z"
  }
}
```

**失败响应** (401):

```json
{
  "success": false,
  "error": "未授权"
}
```

**使用示例**:

```javascript
const response = await fetch('/api/user/profile', {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    full_name: '张三',
    bio: '这是我的个人简介',
    avatar_url: 'https://example.com/avatar.jpg'
  })
})

const data = await response.json()
if (data.success) {
  console.log('更新成功:', data.data)
}
```

---

## 小程序/APP 集成示例

### 小程序（微信小程序）

```javascript
// 注册
wx.request({
  url: 'https://your-domain.com/api/auth/register',
  method: 'POST',
  data: {
    email: 'user@example.com',
    password: 'password123',
    role: 'user'
  },
  success(res) {
    if (res.data.success) {
      wx.showToast({ title: res.data.message })
    }
  }
})

// 登录
wx.request({
  url: 'https://your-domain.com/api/auth/login',
  method: 'POST',
  data: {
    email: 'user@example.com',
    password: 'password123'
  },
  success(res) {
    if (res.data.success) {
      // 保存 session
      wx.setStorageSync('userSession', res.data.data)
      wx.navigateTo({ url: '/pages/profile/index' })
    }
  }
})
```

### React Native / Expo

```javascript
import AsyncStorage from '@react-native-async-storage/async-storage'

// 登录
const login = async (email, password) => {
  try {
    const response = await fetch('https://your-domain.com/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    })
    
    const data = await response.json()
    
    if (data.success) {
      // 保存用户信息
      await AsyncStorage.setItem('user', JSON.stringify(data.data))
      navigation.navigate('Profile')
    } else {
      Alert.alert('登录失败', data.error)
    }
  } catch (error) {
    console.error('登录错误:', error)
  }
}

// 获取用户信息
const getProfile = async () => {
  try {
    const response = await fetch('https://your-domain.com/api/user/profile')
    const data = await response.json()
    
    if (data.success) {
      return data.data
    }
  } catch (error) {
    console.error('获取用户信息错误:', error)
  }
}
```

---

## 错误处理

### 常见错误代码

| 错误信息 | 说明 | 解决方案 |
|---------|------|---------|
| 邮箱和密码不能为空 | 必填字段缺失 | 检查请求参数 |
| 邮箱已被注册 | 邮箱重复 | 使用其他邮箱或尝试登录 |
| 邮箱或密码错误 | 登录凭证错误 | 检查邮箱和密码 |
| 未授权 | 未登录或会话过期 | 重新登录 |
| 服务器错误 | 服务器内部错误 | 稍后重试或联系管理员 |

### 错误处理示例

```javascript
async function callAPI(url, options) {
  try {
    const response = await fetch(url, options)
    const data = await response.json()
    
    if (!data.success) {
      // 处理业务错误
      if (response.status === 401) {
        // 未授权，跳转到登录页
        router.push('/login')
      } else {
        // 显示错误信息
        toast.error(data.error || '请求失败')
      }
      return null
    }
    
    return data.data
  } catch (error) {
    // 处理网络错误
    console.error('网络错误:', error)
    toast.error('网络连接失败，请检查您的网络')
    return null
  }
}
```

---

## 后续扩展接口

以下是后续可以添加的接口建议：

### 认证相关

- `POST /api/auth/forgot-password` - 忘记密码
- `POST /api/auth/reset-password` - 重置密码
- `POST /api/auth/resend-verification` - 重新发送验证邮件
- `POST /api/auth/change-password` - 修改密码

### 文章管理（作者）

- `GET /api/posts` - 获取文章列表
- `POST /api/posts` - 创建文章
- `GET /api/posts/:id` - 获取文章详情
- `PUT /api/posts/:id` - 更新文章
- `DELETE /api/posts/:id` - 删除文章

### 文件上传

- `POST /api/upload/avatar` - 上传头像
- `POST /api/upload/image` - 上传图片

### 管理后台（管理员）

- `GET /api/admin/users` - 获取用户列表
- `PUT /api/admin/users/:id/role` - 修改用户角色
- `DELETE /api/admin/users/:id` - 删除用户

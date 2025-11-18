# Next.js 16 认证系统

一个基于 Next.js 16 (App Router)、TypeScript、Supabase、Tailwind CSS v4 和 shadcn/ui 构建的现代认证系统。

## 技术栈

- **Next.js 16** - 使用最新的 App Router
- **TypeScript** - 类型安全
- **Supabase** - 认证和数据库
- **Tailwind CSS v4** - 样式框架
- **shadcn/ui** - UI 组件库
- **React Hook Form** - 表单管理
- **Zod** - 数据验证
- **Sonner** - Toast 通知

## 功能特性

### 认证功能
- ✅ 用户注册（支持普通用户和作者角色）
- ✅ 邮箱验证提示（倒计时自动跳转）
- ✅ 用户登录
- ✅ 基于角色的路由重定向
  - 普通用户 → 个人信息页面
  - 作者 → 后台管理页面
- ✅ 退出登录

### 页面
- **首页** - 欢迎页面，包含登录/注册按钮
- **注册页面** - 用户注册表单
- **邮箱验证页面** - 注册成功后的邮箱验证提示
- **登录页面** - 用户登录表单
- **个人信息页面** - 普通用户的个人中心
- **Dashboard 页面** - 作者的后台管理界面

### API 路由
所有 API 统一放在 `/api` 目录下，方便后续扩展到小程序或 APP：

- `POST /api/auth/register` - 用户注册
- `POST /api/auth/login` - 用户登录
- `POST /api/auth/logout` - 退出登录
- `GET /api/user/profile` - 获取用户信息
- `PUT /api/user/profile` - 更新用户信息

## 项目结构

```
/src
  /app
    /(auth)              # 认证路由组
      /login             # 登录页面
      /register          # 注册页面
      /verify-email      # 邮箱验证页面
    /(protected)         # 受保护路由组
      /profile           # 个人信息页面
      /dashboard         # 后台管理页面
    /api                 # API 路由
      /auth              # 认证相关 API
        /register
        /login
        /logout
      /user              # 用户相关 API
        /profile
    layout.tsx
    page.tsx             # 首页
    globals.css
  /components
    /ui                  # shadcn/ui 组件
      /button.tsx
      /card.tsx
      /input.tsx
      /label.tsx
    /auth                # 认证相关组件
      /logout-button.tsx
  /lib
    /supabase            # Supabase 客户端
      /client.ts         # 客户端
      /server.ts         # 服务端
      /middleware.ts     # 中间件
    /utils.ts            # 工具函数
  /types
    /index.ts            # TypeScript 类型定义
  /middleware.ts         # Next.js 中间件
```

## 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

复制 `.env.example` 为 `.env.local` 并填入您的 Supabase 配置：

```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### 3. 设置 Supabase 数据库

在 Supabase SQL 编辑器中执行以下 SQL 语句创建必要的表：

```sql
-- 创建 profiles 表
CREATE TABLE profiles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'author', 'admin')),
  full_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  UNIQUE(user_id)
);

-- 启用 RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 创建策略
CREATE POLICY "Users can view their own profile" 
  ON profiles FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile" 
  ON profiles FOR UPDATE 
  USING (auth.uid() = user_id);

-- 创建索引
CREATE INDEX idx_profiles_user_id ON profiles(user_id);
CREATE INDEX idx_profiles_role ON profiles(role);
```

### 4. 启动开发服务器

```bash
npm run dev
```

访问 [http://localhost:3000](http://localhost:3000) 查看应用。

## 开发说明

### MVP 开发模式

本项目采用 MVP（Minimum Viable Product）开发模式，专注于核心功能实现：

1. **用户认证流程** - 注册、验证、登录
2. **角色权限管理** - 普通用户和作者的不同路由
3. **统一 API 接口** - 前后端分离，方便扩展

### 扩展建议

后续可以根据需求添加以下功能：

- [ ] 忘记密码功能
- [ ] 个人信息编辑
- [ ] 头像上传
- [ ] 文章管理系统
- [ ] 评论系统
- [ ] 数据统计
- [ ] 管理员后台

### 添加新的 API 路由

所有 API 路由遵循 RESTful 规范，统一返回格式：

```typescript
{
  success: boolean
  data?: any
  error?: string
  message?: string
}
```

### 中间件保护

项目使用 Next.js 中间件进行路由保护：

- 未登录用户访问受保护页面会被重定向到登录页
- 已登录用户访问认证页面会被重定向到对应的首页
- 普通用户访问 Dashboard 会被重定向到个人信息页

## 部署

### Vercel 部署

1. 将代码推送到 GitHub
2. 在 Vercel 导入项目
3. 配置环境变量
4. 部署

### 其他平台

本项目可以部署到任何支持 Next.js 的平台，如：

- Netlify
- Railway
- Render
- AWS Amplify

## 许可证

MIT

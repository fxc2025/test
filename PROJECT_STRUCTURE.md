# 项目结构详解

## 📂 完整目录结构

```
nextjs-auth-app/
├── .git/                       # Git 版本控制
├── .gitignore                  # Git 忽略文件配置
├── .npmrc                      # npm 配置（legacy-peer-deps）
├── .env.example                # 环境变量示例
├── .env.local                  # 本地环境变量（不提交）
├── .eslintrc.json             # ESLint 配置
├── package.json               # 项目依赖和脚本
├── package-lock.json          # 依赖锁定文件
├── tsconfig.json              # TypeScript 配置
├── next.config.ts             # Next.js 配置
├── tailwind.config.ts         # Tailwind CSS v4 配置
├── postcss.config.mjs         # PostCSS 配置
├── README.md                  # 项目说明文档
├── QUICKSTART.md              # 快速启动指南
├── SETUP.md                   # 详细配置指南
├── API.md                     # API 接口文档
├── PROJECT_STRUCTURE.md       # 本文件（项目结构说明）
├── supabase-schema.sql        # Supabase 数据库结构
│
├── node_modules/              # 依赖包（自动生成）
│
└── src/                       # 源代码目录
    ├── middleware.ts          # Next.js 中间件（路由保护）
    │
    ├── types/                 # TypeScript 类型定义
    │   └── index.ts           # 全局类型（User, Profile, API Response 等）
    │
    ├── lib/                   # 工具库
    │   ├── utils.ts           # 通用工具函数（cn 等）
    │   └── supabase/          # Supabase 客户端配置
    │       ├── client.ts      # 客户端（浏览器）
    │       ├── server.ts      # 服务端（Server Components）
    │       └── middleware.ts  # 中间件专用
    │
    ├── components/            # React 组件
    │   ├── ui/                # shadcn/ui 基础组件
    │   │   ├── button.tsx     # 按钮组件
    │   │   ├── card.tsx       # 卡片组件
    │   │   ├── input.tsx      # 输入框组件
    │   │   └── label.tsx      # 标签组件
    │   │
    │   └── auth/              # 认证相关组件
    │       └── logout-button.tsx  # 退出登录按钮
    │
    └── app/                   # Next.js App Router 页面
        ├── layout.tsx         # 根布局（全局）
        ├── page.tsx           # 首页（欢迎页）
        ├── globals.css        # 全局样式（Tailwind）
        │
        ├── (auth)/            # 认证路由组（不影响 URL）
        │   ├── login/         # 登录页面
        │   │   └── page.tsx
        │   ├── register/      # 注册页面
        │   │   └── page.tsx
        │   └── verify-email/  # 邮箱验证页面
        │       └── page.tsx
        │
        ├── (protected)/       # 受保护路由组（需要登录）
        │   ├── profile/       # 个人信息页面
        │   │   └── page.tsx
        │   └── dashboard/     # 管理后台页面
        │       └── page.tsx
        │
        └── api/               # API 路由
            ├── auth/          # 认证相关 API
            │   ├── register/  # 注册接口
            │   │   └── route.ts
            │   ├── login/     # 登录接口
            │   │   └── route.ts
            │   └── logout/    # 退出登录接口
            │       └── route.ts
            │
            └── user/          # 用户相关 API
                └── profile/   # 用户信息接口
                    └── route.ts
```

---

## 📋 文件说明

### 配置文件

| 文件 | 说明 |
|------|------|
| `package.json` | 项目依赖、脚本命令、版本信息 |
| `tsconfig.json` | TypeScript 编译配置 |
| `next.config.ts` | Next.js 框架配置 |
| `tailwind.config.ts` | Tailwind CSS v4 配置 |
| `postcss.config.mjs` | PostCSS 配置（Tailwind 需要） |
| `.eslintrc.json` | ESLint 代码规范配置 |
| `.gitignore` | Git 忽略文件列表 |
| `.npmrc` | npm 配置（自动使用 legacy-peer-deps） |
| `.env.local` | 环境变量（Supabase 配置） |

### 核心代码

#### 中间件 (`src/middleware.ts`)
```typescript
// 功能：
- 自动刷新用户会话
- 保护受限路由（未登录跳转登录）
- 基于角色的访问控制（普通用户不能访问 dashboard）
- 自动重定向（已登录访问登录页则跳转首页）
```

#### 类型定义 (`src/types/index.ts`)
```typescript
// 包含：
- UserRole: 用户角色类型
- User: 用户数据结构
- Profile: 用户资料结构
- RegisterFormData: 注册表单数据
- LoginFormData: 登录表单数据
- ApiResponse: 统一 API 响应格式
```

#### Supabase 配置 (`src/lib/supabase/`)

| 文件 | 用途 | 使用场景 |
|------|------|----------|
| `client.ts` | 客户端实例 | Client Components、客户端操作 |
| `server.ts` | 服务端实例 | Server Components、API Routes |
| `middleware.ts` | 中间件实例 | Next.js 中间件 |

#### UI 组件 (`src/components/ui/`)

基于 shadcn/ui 的基础组件库：

- **Button** - 支持多种样式变体（default, outline, ghost, link 等）
- **Card** - 卡片容器（Header, Content, Footer）
- **Input** - 输入框（支持各种类型）
- **Label** - 表单标签

---

## 🗺️ 路由结构

### 公开路由

| 路由 | 文件 | 说明 |
|------|------|------|
| `/` | `app/page.tsx` | 首页（欢迎页） |
| `/login` | `app/(auth)/login/page.tsx` | 登录页面 |
| `/register` | `app/(auth)/register/page.tsx` | 注册页面 |
| `/verify-email` | `app/(auth)/verify-email/page.tsx` | 邮箱验证提示页 |

### 受保护路由

| 路由 | 文件 | 权限要求 |
|------|------|----------|
| `/profile` | `app/(protected)/profile/page.tsx` | 所有已登录用户 |
| `/dashboard` | `app/(protected)/dashboard/page.tsx` | 仅 author/admin |

### API 路由

| 端点 | 文件 | 方法 | 说明 |
|------|------|------|------|
| `/api/auth/register` | `app/api/auth/register/route.ts` | POST | 用户注册 |
| `/api/auth/login` | `app/api/auth/login/route.ts` | POST | 用户登录 |
| `/api/auth/logout` | `app/api/auth/logout/route.ts` | POST | 退出登录 |
| `/api/user/profile` | `app/api/user/profile/route.ts` | GET, PUT | 获取/更新用户信息 |

---

## 🔐 权限系统

### 路由组说明

#### `(auth)` 路由组
- **不影响 URL 结构**
- 包含登录、注册、验证等认证页面
- 已登录用户访问会自动重定向

#### `(protected)` 路由组
- **不影响 URL 结构**
- 包含需要登录才能访问的页面
- 未登录用户会被重定向到登录页

### 角色权限矩阵

| 页面 | user | author | admin |
|------|------|--------|-------|
| `/` | ✅ | ✅ | ✅ |
| `/login` | ❌* | ❌* | ❌* |
| `/register` | ❌* | ❌* | ❌* |
| `/profile` | ✅ | ✅ | ✅ |
| `/dashboard` | ❌ | ✅ | ✅ |

> *已登录用户访问认证页面会自动跳转到首页

---

## 📊 数据流程

### 注册流程
```
[客户端表单]
    ↓
[POST /api/auth/register]
    ↓
[Supabase Admin API]
    ↓
[创建 auth.users 记录]
    ↓
[触发器：创建 profiles 记录]
    ↓
[返回成功响应]
    ↓
[跳转邮箱验证页面]
    ↓
[10秒倒计时]
    ↓
[自动跳转登录页]
```

### 登录流程
```
[客户端表单]
    ↓
[POST /api/auth/login]
    ↓
[Supabase Auth API]
    ↓
[验证邮箱密码]
    ↓
[查询 profiles 表获取角色]
    ↓
[返回用户信息 + redirectTo]
    ↓
[客户端根据角色跳转]
    ├─ user → /profile
    └─ author/admin → /dashboard
```

### 中间件保护流程
```
[用户访问页面]
    ↓
[middleware.ts 拦截]
    ↓
[Supabase 验证会话]
    ↓
[获取用户信息]
    ↓
[检查路由权限]
    ├─ 未登录访问受保护页面 → 重定向登录
    ├─ 已登录访问认证页面 → 重定向首页
    ├─ user 访问 dashboard → 重定向 profile
    └─ 权限正确 → 允许访问
```

---

## 🎨 样式系统

### Tailwind CSS v4

项目使用 Tailwind CSS v4，配置文件：
- `tailwind.config.ts` - 主题配置
- `postcss.config.mjs` - PostCSS 插件
- `src/app/globals.css` - 全局样式和 CSS 变量

### CSS 变量

在 `globals.css` 中定义了设计系统的颜色变量：

```css
:root {
  --background
  --foreground
  --primary
  --secondary
  --muted
  --accent
  --destructive
  --border
  --ring
  ...
}
```

### 工具函数

`cn()` 函数用于合并 className：

```typescript
import { cn } from '@/lib/utils'

<div className={cn('base-class', condition && 'conditional-class')} />
```

---

## 🔌 可扩展性

### 添加新页面

```typescript
// src/app/(protected)/new-page/page.tsx
export default async function NewPage() {
  // Server Component
  return <div>New Protected Page</div>
}
```

### 添加新 API

```typescript
// src/app/api/new-endpoint/route.ts
import { NextRequest, NextResponse } from 'next/server'

export async function GET(request: NextRequest) {
  return NextResponse.json({ success: true })
}
```

### 添加新组件

```typescript
// src/components/ui/new-component.tsx
import { cn } from '@/lib/utils'

export function NewComponent({ className, ...props }) {
  return <div className={cn('base-styles', className)} {...props} />
}
```

---

## 📦 依赖说明

### 核心依赖

- `next@^15.0.3` - Next.js 16 框架
- `react@^19.0.0` - React 19
- `@supabase/supabase-js` - Supabase 客户端
- `@supabase/ssr` - Supabase SSR 支持
- `tailwindcss@^4.0.0` - Tailwind CSS v4

### UI 相关

- `class-variance-authority` - 组件变体管理
- `clsx` - className 条件合并
- `tailwind-merge` - Tailwind 类名合并
- `lucide-react` - 图标库
- `sonner` - Toast 通知

### 表单相关

- `react-hook-form` - 表单管理
- `@hookform/resolvers` - 表单验证解析器
- `zod` - 数据验证

---

## 🚀 构建流程

### 开发模式
```bash
npm run dev
# 启动 Next.js 开发服务器
# 支持热重载、Fast Refresh
```

### 生产构建
```bash
npm run build
# 1. 编译 TypeScript
# 2. 打包 Next.js 应用
# 3. 优化资源文件
# 4. 生成 .next 目录
```

### 生产运行
```bash
npm start
# 运行构建后的应用
```

---

## 📝 代码规范

### 命名约定

- **组件文件**: PascalCase（如 `Button.tsx`）
- **工具函数**: camelCase（如 `createClient`）
- **常量**: UPPER_SNAKE_CASE（如 `API_URL`）
- **类型/接口**: PascalCase（如 `UserRole`）

### 导入顺序

```typescript
// 1. React/Next.js
import { useState } from 'react'
import Link from 'next/link'

// 2. 第三方库
import { toast } from 'sonner'

// 3. 项目内部（使用别名 @/）
import { Button } from '@/components/ui/button'
import { createClient } from '@/lib/supabase/client'
import type { User } from '@/types'
```

### 组件结构

```typescript
'use client' // 如果是客户端组件

import ...

export default function Component() {
  // 1. Hooks
  const [state, setState] = useState()
  
  // 2. 函数
  const handleClick = () => {}
  
  // 3. 副作用
  useEffect(() => {}, [])
  
  // 4. 返回 JSX
  return <div>...</div>
}
```

---

这个项目结构遵循 Next.js 16 App Router 的最佳实践，采用清晰的目录组织和模块化设计，便于维护和扩展。

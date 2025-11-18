# 项目配置指南

## 1. Supabase 配置

### 创建 Supabase 项目

1. 访问 [Supabase](https://supabase.com) 并创建账号
2. 创建一个新项目
3. 等待项目初始化完成

### 获取配置信息

在 Supabase 项目设置中获取以下信息：

1. **Project URL** - 在 Settings > API > Project URL
2. **Anon Key** - 在 Settings > API > Project API keys > anon public
3. **Service Role Key** - 在 Settings > API > Project API keys > service_role

### 配置环境变量

将 `.env.example` 复制为 `.env.local`：

```bash
cp .env.example .env.local
```

编辑 `.env.local` 文件，填入您的 Supabase 配置：

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### 执行数据库迁移

1. 登录 Supabase Dashboard
2. 进入 SQL Editor
3. 复制 `supabase-schema.sql` 文件的内容
4. 粘贴到 SQL Editor 并执行

这将创建：
- `profiles` 表
- Row Level Security (RLS) 策略
- 自动创建 profile 的触发器
- 必要的索引

### 配置邮件验证

1. 在 Supabase Dashboard 中进入 Authentication > URL Configuration
2. 设置 Site URL 为您的应用域名（开发环境使用 `http://localhost:3000`）
3. 在 Authentication > Email Templates 中自定义邮件模板（可选）

## 2. 本地开发

### 安装依赖

```bash
npm install --legacy-peer-deps
```

### 启动开发服务器

```bash
npm run dev
```

访问 [http://localhost:3000](http://localhost:3000)

### 开发工具

- **类型检查**: `npm run type-check`
- **代码检查**: `npm run lint`
- **构建**: `npm run build`
- **生产运行**: `npm start`

## 3. 项目结构说明

### 路由组织

- `(auth)` - 认证相关页面（登录、注册、验证）
- `(protected)` - 需要登录的页面（个人中心、管理后台）
- `api` - API 路由

### 中间件保护

项目使用 Next.js 中间件 (`src/middleware.ts`) 实现：

1. 自动刷新用户会话
2. 保护受限路由
3. 基于角色的访问控制
4. 自动重定向

### 角色系统

系统支持三种角色：

- **user** - 普通用户
  - 可访问个人信息页面
  - 查看和编辑自己的资料

- **author** - 作者
  - 拥有普通用户的所有权限
  - 可访问后台管理面板
  - 可以创建和管理内容

- **admin** - 管理员
  - 拥有作者的所有权限
  - 可以管理所有用户和内容

## 4. API 接口说明

所有 API 返回统一格式：

```typescript
{
  success: boolean
  data?: any
  error?: string
  message?: string
}
```

### 认证接口

#### 注册
```
POST /api/auth/register
Body: { email, password, role }
```

#### 登录
```
POST /api/auth/login
Body: { email, password }
```

#### 退出登录
```
POST /api/auth/logout
```

### 用户接口

#### 获取用户信息
```
GET /api/user/profile
```

#### 更新用户信息
```
PUT /api/user/profile
Body: { full_name, bio, avatar_url }
```

## 5. 测试账号

注册后可以使用以下步骤测试：

1. **注册普通用户**
   - 选择角色：普通用户
   - 注册后会看到邮箱验证提示
   - 10 秒后自动跳转到登录页

2. **注册作者账号**
   - 选择角色：作者
   - 登录后会进入 Dashboard

3. **测试功能**
   - 查看个人信息
   - 测试退出登录
   - 测试路由保护

## 6. 常见问题

### Q: 邮件发送失败？
A: 检查 Supabase 的邮件配置，或者使用自定义 SMTP 服务器。

### Q: 登录后无法访问受保护页面？
A: 检查 profile 表是否正确创建，以及触发器是否正常工作。

### Q: Tailwind CSS 样式不生效？
A: 确保已正确安装 Tailwind CSS v4 的依赖，并检查 `postcss.config.mjs` 配置。

### Q: TypeScript 报错？
A: 运行 `npm run type-check` 查看详细错误信息。

## 7. 部署到生产环境

### Vercel 部署

1. 将代码推送到 GitHub
2. 在 Vercel 导入项目
3. 配置环境变量（同 `.env.local`）
4. 更新 Supabase 的 Site URL 为生产域名
5. 部署

### 环境变量配置

确保在生产环境配置以下变量：

```env
NEXT_PUBLIC_SUPABASE_URL=your_production_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_production_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_production_service_role_key
NEXT_PUBLIC_APP_URL=https://your-production-domain.com
```

## 8. 后续开发建议

### MVP 完成后可以添加：

1. **认证功能增强**
   - 忘记密码
   - 重新发送验证邮件
   - 社交登录（Google, GitHub 等）

2. **用户管理**
   - 个人资料编辑
   - 头像上传
   - 密码修改

3. **内容管理**
   - 文章 CRUD
   - 分类和标签
   - 富文本编辑器

4. **权限管理**
   - 细粒度权限控制
   - 用户角色管理
   - 操作日志

5. **数据分析**
   - 用户行为统计
   - 内容阅读量
   - Dashboard 数据可视化

## 9. 技术支持

如有问题，请参考：

- [Next.js 文档](https://nextjs.org/docs)
- [Supabase 文档](https://supabase.com/docs)
- [Tailwind CSS 文档](https://tailwindcss.com/docs)
- [shadcn/ui 文档](https://ui.shadcn.com)

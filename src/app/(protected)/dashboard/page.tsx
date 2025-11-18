import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import LogoutButton from '@/components/auth/logout-button'

export default async function DashboardPage() {
  const supabase = await createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    redirect('/login')
  }

  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('user_id', user.id)
    .single()

  if (profile?.role !== 'author' && profile?.role !== 'admin') {
    redirect('/profile')
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-50 to-pink-100 p-4">
      <div className="max-w-6xl mx-auto space-y-6 py-8">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold">作者管理后台</h1>
            <p className="text-muted-foreground">欢迎回来，{user.email}</p>
          </div>
          <LogoutButton />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">文章数量</CardTitle>
              <CardDescription>已发布的文章总数</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">0</p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg">阅读量</CardTitle>
              <CardDescription>文章总阅读次数</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">0</p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg">评论数</CardTitle>
              <CardDescription>收到的评论总数</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">0</p>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>账号信息</CardTitle>
            <CardDescription>您的作者账号详细信息</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-1">
                <p className="text-sm font-medium text-muted-foreground">用户 ID</p>
                <p className="text-sm font-mono bg-muted p-2 rounded">{user.id}</p>
              </div>
              <div className="space-y-1">
                <p className="text-sm font-medium text-muted-foreground">邮箱地址</p>
                <p className="text-sm">{user.email}</p>
              </div>
              <div className="space-y-1">
                <p className="text-sm font-medium text-muted-foreground">账号类型</p>
                <p className="text-sm">
                  <span className="inline-flex items-center rounded-full bg-purple-100 px-3 py-1 text-xs font-medium text-purple-800">
                    {profile?.role === 'author' ? '作者' : profile?.role === 'admin' ? '管理员' : profile?.role}
                  </span>
                </p>
              </div>
              <div className="space-y-1">
                <p className="text-sm font-medium text-muted-foreground">注册时间</p>
                <p className="text-sm">
                  {new Date(user.created_at).toLocaleString('zh-CN')}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>快速操作</CardTitle>
            <CardDescription>常用功能快捷入口</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <button className="p-4 border rounded-lg hover:bg-accent transition-colors text-left">
                <h3 className="font-medium">创建文章</h3>
                <p className="text-sm text-muted-foreground mt-1">发布新的文章内容</p>
              </button>
              <button className="p-4 border rounded-lg hover:bg-accent transition-colors text-left">
                <h3 className="font-medium">管理文章</h3>
                <p className="text-sm text-muted-foreground mt-1">编辑和管理已发布文章</p>
              </button>
              <button className="p-4 border rounded-lg hover:bg-accent transition-colors text-left">
                <h3 className="font-medium">查看统计</h3>
                <p className="text-sm text-muted-foreground mt-1">查看详细数据分析</p>
              </button>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

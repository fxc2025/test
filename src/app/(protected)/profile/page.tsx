import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import LogoutButton from '@/components/auth/logout-button'

export default async function ProfilePage() {
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

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <div className="max-w-4xl mx-auto space-y-6 py-8">
        <div className="flex justify-between items-center">
          <h1 className="text-3xl font-bold">个人中心</h1>
          <LogoutButton />
        </div>

        <Card>
          <CardHeader>
            <CardTitle>用户信息</CardTitle>
            <CardDescription>您的账号详细信息</CardDescription>
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
                  <span className="inline-flex items-center rounded-full bg-blue-100 px-3 py-1 text-xs font-medium text-blue-800">
                    {profile?.role === 'user' ? '普通用户' : profile?.role}
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

            {profile?.full_name && (
              <div className="space-y-1">
                <p className="text-sm font-medium text-muted-foreground">姓名</p>
                <p className="text-sm">{profile.full_name}</p>
              </div>
            )}

            {profile?.bio && (
              <div className="space-y-1">
                <p className="text-sm font-medium text-muted-foreground">个人简介</p>
                <p className="text-sm">{profile.bio}</p>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>账号状态</CardTitle>
            <CardDescription>您的账号验证状态</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-2">
              {user.email_confirmed_at ? (
                <>
                  <div className="w-2 h-2 rounded-full bg-green-500"></div>
                  <span className="text-sm">邮箱已验证</span>
                </>
              ) : (
                <>
                  <div className="w-2 h-2 rounded-full bg-yellow-500"></div>
                  <span className="text-sm">邮箱待验证</span>
                </>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

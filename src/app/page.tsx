import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'

export default function HomePage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100">
      <Card className="w-full max-w-md mx-4">
        <CardHeader className="text-center">
          <CardTitle className="text-3xl font-bold">欢迎来到</CardTitle>
          <CardDescription className="text-lg">Next.js 认证系统</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-center text-muted-foreground">
            这是一个基于 Next.js 16、Supabase 和 Tailwind CSS v4 构建的现代认证系统
          </p>
          <div className="flex flex-col gap-3">
            <Link href="/login" className="w-full">
              <Button className="w-full" size="lg">
                登录
              </Button>
            </Link>
            <Link href="/register" className="w-full">
              <Button variant="outline" className="w-full" size="lg">
                注册账号
              </Button>
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

'use client'

import { useEffect, useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import Link from 'next/link'

function VerifyEmailContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const email = searchParams.get('email')
  const [countdown, setCountdown] = useState(10)

  useEffect(() => {
    if (countdown === 0) {
      router.push('/login')
      return
    }

    const timer = setTimeout(() => {
      setCountdown(countdown - 1)
    }, 1000)

    return () => clearTimeout(timer)
  }, [countdown, router])

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100">
      <Card className="w-full max-w-md mx-4">
        <CardHeader className="text-center">
          <div className="mx-auto mb-4 w-12 h-12 rounded-full bg-green-100 flex items-center justify-center">
            <svg
              className="w-6 h-6 text-green-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
          <CardTitle>注册成功！</CardTitle>
          <CardDescription>请验证您的邮箱地址</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="text-center space-y-2">
            <p className="text-sm text-muted-foreground">
              我们已向 <strong className="text-foreground">{email}</strong> 发送了一封验证邮件
            </p>
            <p className="text-sm text-muted-foreground">
              请点击邮件中的链接以验证您的账号
            </p>
          </div>

          <div className="bg-blue-50 border border-blue-200 rounded-md p-4 text-center">
            <p className="text-sm text-blue-900 font-medium">
              {countdown} 秒后自动跳转到登录页面
            </p>
          </div>

          <div className="space-y-2">
            <Link href="/login" className="block">
              <Button className="w-full">立即前往登录</Button>
            </Link>
            <Link href="/" className="block">
              <Button variant="outline" className="w-full">
                返回首页
              </Button>
            </Link>
          </div>

          <div className="text-center">
            <p className="text-xs text-muted-foreground">
              没有收到邮件？请检查垃圾邮件文件夹
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

export default function VerifyEmailPage() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <VerifyEmailContent />
    </Suspense>
  )
}

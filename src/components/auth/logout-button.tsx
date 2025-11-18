'use client'

import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'

export default function LogoutButton() {
  const router = useRouter()

  const handleLogout = async () => {
    try {
      const response = await fetch('/api/auth/logout', {
        method: 'POST',
      })

      const data = await response.json()

      if (data.success) {
        toast.success(data.message)
        router.push('/login')
        router.refresh()
      } else {
        toast.error(data.error || '退出登录失败')
      }
    } catch (error) {
      console.error('Logout error:', error)
      toast.error('退出登录失败，请稍后再试')
    }
  }

  return (
    <Button variant="outline" onClick={handleLogout}>
      退出登录
    </Button>
  )
}

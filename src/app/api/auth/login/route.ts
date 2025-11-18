import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import type { ApiResponse } from '@/types'

export async function POST(request: NextRequest) {
  try {
    const { email, password } = await request.json()

    if (!email || !password) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '邮箱和密码不能为空' },
        { status: 400 }
      )
    }

    const supabase = await createClient()

    const { data: authData, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (signInError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '邮箱或密码错误' },
        { status: 401 }
      )
    }

    if (!authData.user) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '登录失败' },
        { status: 500 }
      )
    }

    const { data: profile } = await supabase
      .from('profiles')
      .select('role')
      .eq('user_id', authData.user.id)
      .single()

    const redirectTo = profile?.role === 'author' || profile?.role === 'admin'
      ? '/dashboard'
      : '/profile'

    return NextResponse.json<ApiResponse>(
      {
        success: true,
        message: '登录成功',
        data: {
          user: authData.user,
          redirectTo,
        },
      },
      { status: 200 }
    )
  } catch (error) {
    console.error('Login error:', error)
    return NextResponse.json<ApiResponse>(
      { success: false, error: '服务器错误，请稍后再试' },
      { status: 500 }
    )
  }
}

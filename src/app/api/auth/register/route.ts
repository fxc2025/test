import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import type { ApiResponse } from '@/types'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(request: NextRequest) {
  try {
    const { email, password, role = 'user' } = await request.json()

    if (!email || !password) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '邮箱和密码不能为空' },
        { status: 400 }
      )
    }

    const { data: authData, error: signUpError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: false,
      user_metadata: {
        role,
      },
    })

    if (signUpError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: signUpError.message },
        { status: 400 }
      )
    }

    if (!authData.user) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '创建用户失败' },
        { status: 500 }
      )
    }

    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .insert({
        user_id: authData.user.id,
        role,
      })

    if (profileError) {
      console.error('Profile creation error:', profileError)
    }

    return NextResponse.json<ApiResponse>(
      {
        success: true,
        message: '注册成功！请检查您的邮箱以验证账号。',
        data: { userId: authData.user.id },
      },
      { status: 201 }
    )
  } catch (error) {
    console.error('Registration error:', error)
    return NextResponse.json<ApiResponse>(
      { success: false, error: '服务器错误，请稍后再试' },
      { status: 500 }
    )
  }
}

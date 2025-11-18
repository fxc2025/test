import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import type { ApiResponse } from '@/types'

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient()

    const { error } = await supabase.auth.signOut()

    if (error) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: error.message },
        { status: 400 }
      )
    }

    return NextResponse.json<ApiResponse>(
      { success: true, message: '退出登录成功' },
      { status: 200 }
    )
  } catch (error) {
    console.error('Logout error:', error)
    return NextResponse.json<ApiResponse>(
      { success: false, error: '服务器错误，请稍后再试' },
      { status: 500 }
    )
  }
}

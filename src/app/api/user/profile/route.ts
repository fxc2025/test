import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import type { ApiResponse } from '@/types'

export async function GET(request: NextRequest) {
  try {
    const supabase = await createClient()

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser()

    if (userError || !user) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '未授权' },
        { status: 401 }
      )
    }

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (profileError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '获取用户信息失败' },
        { status: 500 }
      )
    }

    return NextResponse.json<ApiResponse>(
      {
        success: true,
        data: {
          user,
          profile,
        },
      },
      { status: 200 }
    )
  } catch (error) {
    console.error('Get profile error:', error)
    return NextResponse.json<ApiResponse>(
      { success: false, error: '服务器错误，请稍后再试' },
      { status: 500 }
    )
  }
}

export async function PUT(request: NextRequest) {
  try {
    const supabase = await createClient()

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser()

    if (userError || !user) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '未授权' },
        { status: 401 }
      )
    }

    const { full_name, bio, avatar_url } = await request.json()

    const { data: profile, error: updateError } = await supabase
      .from('profiles')
      .update({
        full_name,
        bio,
        avatar_url,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', user.id)
      .select()
      .single()

    if (updateError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: '更新用户信息失败' },
        { status: 500 }
      )
    }

    return NextResponse.json<ApiResponse>(
      {
        success: true,
        message: '更新成功',
        data: profile,
      },
      { status: 200 }
    )
  } catch (error) {
    console.error('Update profile error:', error)
    return NextResponse.json<ApiResponse>(
      { success: false, error: '服务器错误，请稍后再试' },
      { status: 500 }
    )
  }
}

export type UserRole = 'user' | 'author' | 'admin'

export interface User {
  id: string
  email: string
  role: UserRole
  created_at: string
  email_confirmed_at?: string
}

export interface Profile {
  id: string
  user_id: string
  full_name?: string
  avatar_url?: string
  bio?: string
  created_at: string
  updated_at: string
}

export interface RegisterFormData {
  email: string
  password: string
  confirmPassword: string
  role?: UserRole
}

export interface LoginFormData {
  email: string
  password: string
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  error?: string
  message?: string
}

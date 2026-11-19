import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

function ceremonyPackage(): unknown | null {
  const packagePath = process.env.CEREMONY_PACKAGE
  if (!packagePath) return null
  const resolvedPath = resolve(process.cwd(), packagePath)
  try {
    return JSON.parse(readFileSync(resolvedPath, 'utf8')) as unknown
  } catch (error) {
    throw new Error(`Could not embed CEREMONY_PACKAGE ${resolvedPath}: ${(error as Error).message}`)
  }
}

export default defineConfig({
  base: './',
  plugins: [react()],
  define: {
    __CEREMONY_PACKAGE__: JSON.stringify(ceremonyPackage()),
  },
  test: {
    environment: 'node',
  },
})

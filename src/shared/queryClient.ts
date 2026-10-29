import { QueryClient } from '@tanstack/react-query'

// Realtime no trae datos: solo invalida queries de este cliente (notify-then-refetch).
export const queryClient = new QueryClient()

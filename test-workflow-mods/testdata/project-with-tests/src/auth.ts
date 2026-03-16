export function checkPermission(user: any, perm: string): boolean {
  return user.permissions.includes(perm);
}

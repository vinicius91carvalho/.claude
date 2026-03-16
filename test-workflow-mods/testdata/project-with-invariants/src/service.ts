import { PERMS } from './permissions';
export function getVendors(user: any) {
  if (!user.hasPermission(PERMS.VENDOR_READ)) throw new Error('forbidden');
  return [];
}

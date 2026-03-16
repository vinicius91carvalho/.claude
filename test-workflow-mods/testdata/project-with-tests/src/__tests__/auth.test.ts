import { checkPermission } from '../auth';
test('returns true for valid permission', () => {
  expect(checkPermission({ permissions: ['read'] }, 'read')).toBe(true);
});

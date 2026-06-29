import { EmployeeProfileBindStatus, EmployeeProfileRow } from '../models/types';

export function resolveEmployeeProfileStatus(
  profile: EmployeeProfileRow | undefined,
): EmployeeProfileBindStatus {
  if (!profile) return 'unbound';
  const status = profile.bind_status;
  if (status === 'pending') return 'pending';
  if (status === 'bound') return 'bound';
  if (status === 'rejected') return 'rejected';
  return 'unbound';
}

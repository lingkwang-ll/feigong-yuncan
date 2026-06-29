import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { employeeProfileToDto, nowIso, userToDto } from '../models/mappers';
import {
  AuthMeDto,
  EmployeeProfileBindStatus,
  EmployeeProfileDto,
  EmployeeProfileRow,
  UserRow,
} from '../models/types';
import { resolveEmployeeProfileStatus } from '../utils/employee-profile.util';

export interface BindEmployeeProfileInput {
  employeeName: string;
  employeeNo: string;
  departmentId: string;
  departmentName: string;
}

export class EmployeeProfileService {
  getByUserId(userId: string): EmployeeProfileRow | undefined {
    return getDb()
      .prepare<[string], EmployeeProfileRow>(
        'SELECT * FROM employee_profiles WHERE user_id = ?',
      )
      .get(userId);
  }

  buildAuthMeDto(user: UserRow): AuthMeDto {
    const profile = this.getByUserId(user.id);
    const employeeProfileStatus = resolveEmployeeProfileStatus(profile);
    return {
      user: userToDto(user),
      employeeProfile: profile ? employeeProfileToDto(profile) : null,
      employeeProfileStatus,
    };
  }

  bindProfile(
    user: UserRow,
    input: BindEmployeeProfileInput,
  ): { profile: EmployeeProfileDto; employeeProfileStatus: EmployeeProfileBindStatus } {
    const existing = this.getByUserId(user.id);
    if (existing && ['bound', 'pending'].includes(existing.bind_status)) {
      throw new Error('ALREADY_BOUND');
    }

    const now = nowIso();
    const db = getDb();

    if (existing?.bind_status === 'rejected') {
      db.prepare(
        `UPDATE employee_profiles SET
           employee_name = ?,
           employee_no = ?,
           phone = ?,
           department_id = ?,
           department_name = ?,
           bind_status = 'bound',
           updated_at = ?
         WHERE user_id = ?`,
      ).run(
        input.employeeName.trim(),
        input.employeeNo.trim(),
        user.phone,
        input.departmentId.trim(),
        input.departmentName.trim(),
        now,
        user.id,
      );
      const updated = this.getByUserId(user.id)!;
      return {
        profile: employeeProfileToDto(updated),
        employeeProfileStatus: 'bound',
      };
    }

    const id = `ep_${nanoid(8)}`;
    db.prepare(
      `INSERT INTO employee_profiles
         (id, user_id, employee_name, employee_no, phone,
          department_id, department_name, role_type, bind_status,
          created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'employee', 'bound', ?, ?)`,
    ).run(
      id,
      user.id,
      input.employeeName.trim(),
      input.employeeNo.trim(),
      user.phone,
      input.departmentId.trim(),
      input.departmentName.trim(),
      now,
      now,
    );

    const profile = this.getByUserId(user.id)!;
    return {
      profile: employeeProfileToDto(profile),
      employeeProfileStatus: 'bound',
    };
  }
}

export const employeeProfileService = new EmployeeProfileService();

import { NextFunction, Request, Response } from 'express';

export class HttpError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const BadRequest = (message: string, code = 'BAD_REQUEST') =>
  new HttpError(400, code, message);

export const NotFound = (message: string, code = 'NOT_FOUND') =>
  new HttpError(404, code, message);

export const Unauthorized = (message = '未登录或登录已失效') =>
  new HttpError(401, 'UNAUTHORIZED', message);

export const Forbidden = (message = '无权访问该资源') =>
  new HttpError(403, 'FORBIDDEN', message);

export const TooManyRequests = (message: string, code = 'TOO_MANY_REQUESTS') =>
  new HttpError(429, code, message);

export function notFoundHandler(req: Request, _res: Response, next: NextFunction) {
  next(NotFound(`Route not found: ${req.method} ${req.originalUrl}`));
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(
  err: unknown,
  _req: Request,
  res: Response,
  // 必须保留 4 个参数，Express 才认为它是错误中间件
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _next: NextFunction,
) {
  if (err instanceof HttpError) {
    res.status(err.status).json({
      error: { code: err.code, message: err.message },
    });
    return;
  }
  console.error('[unhandled error]', err);
  const message = err instanceof Error ? err.message : '服务器内部错误';
  res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message },
  });
}

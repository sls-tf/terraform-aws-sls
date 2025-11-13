// TypeScript type definitions for Serverless Framework
export interface Serverless {
  service: string | { name: string };
  frameworkVersion?: string;
  provider: Provider;
  functions?: { [key: string]: Function };
  custom?: { [key: string]: any };
  resources?: Resources;
}

export interface Provider {
  name: string;
  runtime?: string;
  region?: string;
  stage?: string;
  memorySize?: number;
  timeout?: number;
  environment?: { [key: string]: any };
  iamRoleStatements?: any[];
}

export interface Function {
  handler: string;
  description?: string;
  runtime?: string;
  memorySize?: number;
  timeout?: number;
  environment?: { [key: string]: any };
  events?: Event[];
}

export interface Event {
  http?: HttpEvent;
  schedule?: ScheduleEvent;
  [key: string]: any;
}

export interface HttpEvent {
  path?: string;
  method?: string;
  cors?: boolean | CorsConfig;
}

export interface CorsConfig {
  origins?: string[];
  headers?: string[];
  methods?: string[];
}

export interface ScheduleEvent {
  rate?: string;
  cron?: string;
}

export interface Resources {
  Resources?: { [key: string]: Resource };
}

export interface Resource {
  Type: string;
  Properties?: { [key: string]: any };
}
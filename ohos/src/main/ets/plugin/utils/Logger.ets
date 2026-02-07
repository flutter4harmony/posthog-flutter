/**
 * PostHog Logger for HarmonyOS
 * Provides logging functionality with different log levels
 */
import hilog from '@ohos.hilog';

export class Logger {
  private tag: string;
  private enabled: boolean = true;
  private domain: number = 0x0001; // 日志域

  constructor(tag: string) {
    this.tag = tag;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  debug(message: string, ...args: Object[]): void {
    if (this.enabled) {
      hilog.debug(this.domain, this.tag, message, ...args);
    }
  }

  info(message: string, ...args: Object[]): void {
    if (this.enabled) {
      hilog.info(this.domain, this.tag, message, ...args);
    }
  }

  warn(message: string, ...args: Object[]): void {
    if (this.enabled) {
      hilog.warn(this.domain, this.tag, message, ...args);
    }
  }

  error(message: string, ...args: Object[]): void {
    if (this.enabled) {
      hilog.error(this.domain, this.tag, message, ...args);
    }
  }
}

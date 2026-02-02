/**
 * PostHog Logger for HarmonyOS
 * Provides logging functionality with different log levels
 */
export class Logger {
  private tag: string;
  private enabled: boolean = true;

  constructor(tag: string) {
    this.tag = tag;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  debug(message: string, ...args: Object[]): void {
    if (this.enabled) {
      console.debug(`[${this.tag}] ${message}`, ...args);
    }
  }

  info(message: string, ...args: Object[]): void {
    if (this.enabled) {
      console.info(`[${this.tag}] ${message}`, ...args);
    }
  }

  warn(message: string, ...args: Object[]): void {
    if (this.enabled) {
      console.warn(`[${this.tag}] ${message}`, ...args);
    }
  }

  error(message: string, ...args: Object[]): void {
    if (this.enabled) {
      console.error(`[${this.tag}] ${message}`, ...args);
    }
  }
}

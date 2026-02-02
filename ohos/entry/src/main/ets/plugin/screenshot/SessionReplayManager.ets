import { image } from '@kit.ImageKit';
import { MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { Logger } from '../utils/Logger';
import { ScreenshotCapturer } from './ScreenshotCapturer';

/**
 * Session Replay Manager for HarmonyOS
 * Handles screenshot capture and snapshot sending
 */
export class SessionReplayManager {
  private screenshotCapturer: ScreenshotCapturer;
  private logger: Logger = new Logger('SessionReplayManager');

  // Configuration
  private throttleDelayMs: number = 1000; // 1 second throttle
  private lastCaptureTime: number = 0;
  private maskAllTexts: boolean = true;
  private maskAllImages: boolean = true;

  // Replay state
  private isReplayActive: boolean = false;

  constructor(context: Context) {
    this.screenshotCapturer = new ScreenshotCapturer();
  }

  /**
   * Handle screenshot capture from Flutter
   */
  async handleScreenshotCapture(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      this.logger.info('Handling screenshot capture request');

      const base64 = await this.screenshotCapturer.captureAndConvert();

      if (base64.isEmpty()) {
        result.error('CAPTURE_ERROR', 'Screenshot capture failed or not implemented', null);
        return;
      }

      result.success(base64);
    } catch (e) {
      this.logger.error('Screenshot capture error', e);
      result.error('CAPTURE_ERROR', `Failed to capture screenshot: ${e.message}`, null);
    }
  }

  /**
   * Check if session replay is active
   */
  checkIsActive(): boolean {
    return this.isReplayActive;
  }

  /**
   * Set replay active state
   */
  setActive(active: boolean): void {
    this.isReplayActive = active;
    this.logger.info(`Session replay active: ${active}`);
  }

  /**
   * Get current throttle delay
   */
  getThrottleDelay(): number {
    return this.throttleDelayMs;
  }

  /**
   * Set throttle delay
   */
  setThrottleDelay(delayMs: number): void {
    this.throttleDelayMs = delayMs;
    this.logger.info(`Throttle delay set to ${delayMs}ms`);
  }

  /**
   * Get mask all texts setting
   */
  getMaskAllTexts(): boolean {
    return this.maskAllTexts;
  }

  /**
   * Set mask all texts setting
   */
  setMaskAllTexts(mask: boolean): void {
    this.maskAllTexts = mask;
    this.logger.info(`Mask all texts: ${mask}`);
  }

  /**
   * Get mask all images setting
   */
  getMaskAllImages(): boolean {
    return this.maskAllImages;
  }

  /**
   * Set mask all images setting
   */
  setMaskAllImages(mask: boolean): void {
    this.maskAllImages = mask;
    this.logger.info(`Mask all images: ${mask}`);
  }

  /**
   * Check if should capture (throttle check)
   */
  shouldCapture(): boolean {
    const now = Date.now();
    if (now - this.lastCaptureTime < this.throttleDelayMs) {
      return false;
    }
    this.lastCaptureTime = now;
    return true;
  }

  /**
   * Get singleton instance
   */
  private static instance: SessionReplayManager | null = null;

  static getInstance(context: Context): SessionReplayManager {
    if (SessionReplayManager.instance === null) {
      SessionReplayManager.instance = new SessionReplayManager(context);
    }
    return SessionReplayManager.instance;
  }
}

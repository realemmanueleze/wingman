/**
 * The Wingman pointing contract, inherited from Clicky.
 *
 * The model appends a tag to its response text:
 *   [POINT:x,y:label]           point on the cursor screen
 *   [POINT:x,y:label:screenN]   point on display N (1-based, capture order)
 *   [POINT:none]                nothing worth pointing at
 *
 * Coordinates are in *screenshot pixel space* with a top-left origin. Each
 * shell maps them into its own display coordinate system before animating
 * the buddy cursor.
 */

export type PointTarget = {
  x: number;
  y: number;
  label: string;
  screenNumber?: number;
};

export type PointParseResult = {
  /** Response text with the [POINT:...] tag removed — this is what gets spoken/shown. */
  spokenText: string;
  /** Present when the model chose to point. */
  target?: PointTarget;
};

const POINT_TAG_PATTERN =
  /\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$/;

export function parsePointTag(responseText: string): PointParseResult {
  const match = responseText.match(POINT_TAG_PATTERN);
  if (!match) {
    return { spokenText: responseText.trim() };
  }
  const spokenText = responseText.slice(0, match.index).trim();
  if (match[1] === undefined || match[2] === undefined) {
    return { spokenText };
  }
  return {
    spokenText,
    target: {
      x: Number(match[1]),
      y: Number(match[2]),
      label: match[3]?.trim() ?? "",
      screenNumber: match[4] !== undefined ? Number(match[4]) : undefined,
    },
  };
}

/**
 * System prompt fragment that teaches the model the pointing contract.
 * Appended to vision turns via the gateway `extraSystemPrompt` param.
 */
export const POINTING_PROMPT = `
element pointing:
you have a small cursor that can fly to and point at things on screen. when pointing at a specific UI element would genuinely help the user, append a coordinate tag at the very end of your response, AFTER your spoken text. the screenshot images are labeled with their pixel dimensions; use those dimensions as the coordinate space, origin (0,0) top-left, x rightward, y downward.

format: [POINT:x,y:label] with integer pixel coordinates and a short 1-3 word label. if the element is on a different screen than the cursor, append :screenN using the screen number from the image label. if pointing would not help, append [POINT:none].
`.trim();

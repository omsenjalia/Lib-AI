/** Row shapes. Timestamps are epoch milliseconds; booleans are real booleans. */
export type Role = 'user' | 'assistant' | 'system';

export type Persona = {
  id: number;
  name: string;
  emoji: string;
  systemPrompt: string;
  isBuiltIn: boolean;
  createdAt: number;
};

export type Conversation = {
  id: number;
  title: string;
  /** Catalogue id, not a row id, so a thread survives its model being deleted. */
  modelId: string | null;
  personaId: number | null;
  contextLengthOverride: number | null;
  pinned: boolean;
  createdAt: number;
  updatedAt: number;
};

export type Message = {
  id: number;
  conversationId: number;
  role: Role;
  content: string;
  /** App-private copy of an attached image. The image never leaves the device. */
  imagePath: string | null;
  /** A stored failure, rendered as an error rather than as something the model said. */
  isError: boolean;
  /** Per-message "Render maths" toggle for models that emit bare LaTeX. */
  renderMath: boolean;
  tokenCount: number | null;
  /** True when tokenCount came from the estimator rather than the model's tokeniser. */
  isEstimatedTokens: boolean;
  /** Tokens the model read for this reply (the whole prompt), when known. */
  promptTokens: number | null;
  /** Decode speed of this reply, from llama.cpp's own timings. */
  tokensPerSecond: number | null;
  /** Wall time from send to the last token. */
  generationMs: number | null;
  createdAt: number;
};

export type ModelInstallation = {
  modelId: string;
  quant: string;
  fileName: string;
  localPath: string;
  mmprojPath: string | null;
  sizeBytes: number;
  sha256: string | null;
  repoSha: string | null;
  totalBytes: number;
  downloadedAt: number;
};

export type UpdateCheck = {
  modelId: string;
  lastCheckedAt: number;
  remoteSha: string | null;
  /** Display only. Never starts a download on its own. */
  updateAvailable: boolean;
};

export type ConversationSearchHit = Conversation & { snippet: string | null };

import { files } from '../services/files';
import { backend } from './backend';
import { InferenceEngine } from './engine';

/** The app-wide engine. One resident model at a time. */
export const engine = new InferenceEngine(backend, files);

export type { EngineStage, EngineStatus, GenerationResult, LoadRequest } from './engine';

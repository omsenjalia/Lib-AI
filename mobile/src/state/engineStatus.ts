import { create } from 'zustand';

import { engine, type EngineStatus } from '@/core/engine';

export const useEngineStatus = create<EngineStatus>(() => engine.getStatus());

engine.subscribe((status) => useEngineStatus.setState(status, true));

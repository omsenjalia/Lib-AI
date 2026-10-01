import NetInfo, { type NetInfoState } from '@react-native-community/netinfo';

/**
 * Network state, used for exactly two things: the download Wi-Fi gate and
 * deciding whether an update check is worth attempting. Nothing in chat,
 * history, rendering or export ever asks.
 */
export type NetworkKind = 'offline' | 'unmetered' | 'metered';

export function kindOf(state: NetInfoState): NetworkKind {
  if (state.isConnected === false) return 'offline';
  if (state.type === 'wifi' || state.type === 'ethernet') return 'unmetered';
  if (state.type === 'none') return 'offline';
  return 'metered';
}

export async function currentNetwork(): Promise<NetworkKind> {
  try {
    return kindOf(await NetInfo.fetch());
  } catch {
    // If the platform cannot say, assume online and let the request decide.
    return 'metered';
  }
}

export function onNetworkChange(listener: (kind: NetworkKind) => void): () => void {
  return NetInfo.addEventListener((s) => listener(kindOf(s)));
}

export function describeNetwork(kind: NetworkKind): string {
  return kind === 'offline' ? 'Offline' : kind === 'unmetered' ? 'Wi-Fi' : 'Mobile data';
}

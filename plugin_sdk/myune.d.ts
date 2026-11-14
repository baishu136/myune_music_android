/** SDK 1. Bundle TypeScript to one plain JS file defining globalThis.myunePlugin. */
export interface Song {
  id: string; title: string; artist: string; album: string; durationMs: number | null;
}
export interface Playback {
  song: Song | null; playing: boolean; positionMs: number; durationMs: number;
}
export type View =
  | { type: 'text'; text: string; style?: 'title' | 'muted' }
  | { type: 'button'; text: string; action: string; data?: unknown }
  | { type: 'space'; height?: number }
  | { type: 'column' | 'row' | 'card'; children: View[] };
export interface Event {
  sdk: 1;
  type: 'lifecycle.enable' | 'ui.open' | 'ui.action' | 'menu.action' | 'playback.changed' | 'lyrics.resolve';
  data?: unknown;
  playback?: Playback | null;
}
export interface Api {
  request(method: 'app.capabilities'): Promise<{sdk:1; methods:string[]; features:string[]}>;
  request(method: 'playback.get'): Promise<Playback | null>;
  request(method: 'playback.command', args: {command:'play'|'pause'|'next'|'previous'|'seek';positionMs?:number}): Promise<boolean>;
  request(method: 'library.query', args?: {query?:string; offset?:number; limit?:number}): Promise<{songs:Song[];total:number;nextOffset:number|null}>;
  request(method: 'queue.play'|'queue.append', args: {ids:string[]}): Promise<{count:number}>;
  request(method: 'storage.get', args: {key:string}): Promise<unknown>;
  request(method: 'storage.set', args: {key:string;value:unknown}): Promise<boolean>;
  request(method: 'network.fetch', args: {url:string}): Promise<{status:number;body:string}>;
}
export type Handler = (event: Event, api: Api) => unknown | Promise<unknown>;

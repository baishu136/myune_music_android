globalThis.myunePlugin = async function(event, api) {
  if (event.type === 'lifecycle.enable') return null;
  if (event.type === 'playback.changed') {
    await api.request('storage.set', {key:'lastPlayback', value:event.playback});
    return null;
  }
  const action = event.data?.id;
  if (event.type === 'ui.action') {
    if (action === 'toggle') {
      const state = await api.request('playback.get');
      await api.request('playback.command', {command:state?.playing ? 'pause' : 'play'});
    }
    if (action === 'smart') {
      const page = await api.request('library.query', {limit:100});
      const songs = page.songs.filter(s => !s.durationMs || s.durationMs <= 240000).slice(0,10);
      if (songs.length) await api.request('queue.play', {ids:songs.map(s => s.id)});
    }
    if (action === 'count') {
      const count = await api.request('storage.get', {key:'count'}) || 0;
      await api.request('storage.set', {key:'count',value:count+1});
    }
  }
  const state = await api.request('playback.get');
  const library = await api.request('library.query', {limit:10});
  const count = await api.request('storage.get', {key:'count'}) || 0;
  return {view:{type:'column',children:[
    {type:'text',style:'title',text:state?.song?.title || '尚未选择歌曲'},
    {type:'text',text:(state?.song?.artist || '') + (state?.playing ? ' · 播放中' : ' · 已暂停')},
    {type:'button',text:state?.playing ? '暂停播放' : '继续播放',action:'toggle'},
    {type:'card',children:[
      {type:'text',text:'曲库共 ' + library.total + ' 首'},
      {type:'button',text:'播放短曲精选',action:'smart'},
      {type:'text',text:'从本次查询的前 100 首中选取不超过 4 分钟的歌曲，最多 10 首。',style:'muted'}
    ]},
    {type:'button',text:'计数 ' + count,action:'count'},
    ...library.songs.slice(0,6).map(song => ({type:'text',text:song.title + ' · ' + song.artist}))
  ]}};
};

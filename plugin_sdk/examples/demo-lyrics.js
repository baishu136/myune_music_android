globalThis.myunePlugin = function(event) {
  if (event.type === 'lyrics.resolve') {
    return {lrc:'[00:00.00]插件歌词：' + event.data.title + '\n[00:05.00]这段歌词由独立 JavaScript 插件提供\n[00:12.00]关闭插件后恢复原歌词来源'};
  }
  return {view:{type:'column',children:[
    {type:'text',style:'title',text:'歌词接口示例'},
    {type:'text',text:'此插件会为歌曲返回演示歌词，停用后恢复内置来源。'}
  ]}};
};

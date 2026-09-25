extends RefCounted
## UIの記号（アイコン）。24×24 の SVG を実行時に画像へ変える（素材ファイルは要らない。後で絵に差し替えられる）。
## 形は白で描き、色は使う側で modulate する。Icons.rect("heart",28,色) で TextureRect を返す。
const SVG:={
	# 能力
	"heart":'<path d="M12 21.2 3.6 12.9C1.4 10.7 1.5 7.1 3.9 5.1c2.2-1.8 5.3-1.4 7.2.7l.9 1 .9-1c1.9-2.1 5-2.5 7.2-.7 2.4 2 2.5 5.6.3 7.8z"/>',
	"sword":'<path d="M20.5 2.5 21.5 3.5 11 14.8 9.2 13 20.5 2.5zM20.5 2.5l-5.3.8 5.3-.8zM20.5 2.5v0zM8.2 12.3l3.5 3.5-1.6 1.6-.9-.9-3.6 3.6.5 1.3-1.2 1.2-2.9-2.9 1.2-1.2 1.3.5 3.6-3.6-.9-.9z"/><path d="M21.5 2.5 21 7l-2-2 2.5-2.5z"/>',
	"shield":'<path d="M12 2 20 5v6c0 5.2-3.4 9.3-8 11-4.6-1.7-8-5.8-8-11V5z"/>',
	"magic":'<path d="M12 1.5 14.2 8.8 21.5 11 14.2 13.2 12 20.5 9.8 13.2 2.5 11 9.8 8.8z"/><circle cx="19" cy="19" r="2.2"/><circle cx="5" cy="4.5" r="1.5"/>',
	"wing":'<path d="M2 18c4-.5 7-2.5 9-6 1.5-2.7 4-6.5 11-9-1.2 3-2.2 4.5-4 6 1.5-.1 2.5-.5 3.5-1-1 2.4-2.6 3.8-4.8 4.5 1 .3 1.8.2 3-.2-1.8 2.8-4.4 4.3-7.4 4.4-3 .1-6.3 1-10.3 1.3z"/>',
	"target":'<path fill-rule="evenodd" d="M12 2a10 10 0 1 1 0 20 10 10 0 0 1 0-20zm0 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14zm0 3a4 4 0 1 1 0 8 4 4 0 0 1 0-8zm0 2.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3z"/>',
	# 資源
	"coin":'<path fill-rule="evenodd" d="M12 2a10 10 0 1 1 0 20 10 10 0 0 1 0-20zm0 2.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z"/><path d="M12 6.5 13.4 10.6 17.5 12 13.4 13.4 12 17.5 10.6 13.4 6.5 12 10.6 10.6z"/>',
	"drop":'<path d="M12 2c3.8 4.8 7 8.5 7 12.2A7 7 0 0 1 5 14.2C5 10.5 8.2 6.8 12 2z"/>',
	"gem":'<path d="M6.5 3h11L22 8.5 12 21 2 8.5z"/>',
	# 装備
	"ring":'<path fill-rule="evenodd" d="M12 7.5a7.2 7.2 0 1 1 0 14.4 7.2 7.2 0 0 1 0-14.4zm0 2.6a4.6 4.6 0 1 0 0 9.2 4.6 4.6 0 0 0 0-9.2z"/><path d="M9 2h6l1.8 2.6L12 8.2 7.2 4.6z"/>',
	"armor":'<path d="M8 2.5c1 1.4 2.3 2 4 2s3-.6 4-2l5 2.5-1.8 5-2.2-1V21H7V9l-2.2 1L3 5z"/>',
	# 役割
	"group":'<circle cx="12" cy="7" r="3.4"/><circle cx="5" cy="10" r="2.8"/><circle cx="19" cy="10" r="2.8"/><path d="M5.5 21c0-4 2.9-7.2 6.5-7.2s6.5 3.2 6.5 7.2zM0.8 19c0-3 1.8-5.3 4.2-5.3 1 0 1.9.4 2.6 1-.9 1.2-1.4 2.7-1.6 4.3zM23.2 19c0-3-1.8-5.3-4.2-5.3-1 0-1.9.4-2.6 1 .9 1.2 1.4 2.7 1.6 4.3z"/>',
	"bow":'<path d="M5 2c7 2.5 11 7.5 11 13 0 2-.4 4-1.4 6l-1.8-1c.8-1.7 1.2-3.3 1.2-5 0-4.6-3.3-8.8-9.4-11z"/><path d="M4.5 3 21 19.5l-1.5 1.5L3 4.5z"/><path d="M17 16l5 5-3 .6-.6 2.4-3.2-4.2z"/>',
	"staff":'<path d="M6.2 20.3 14.5 12l1.5 1.5-8.3 8.3z"/><path d="M17 1.5l1.3 3.2 3.2 1.3-3.2 1.3L17 10.5l-1.3-3.2-3.2-1.3 3.2-1.3z"/>',
	"chain":'<path fill-rule="evenodd" d="M9.5 6.5l2.2-2.2a4.6 4.6 0 0 1 6.5 6.5L16 13l-1.8-1.8 2.2-2.2a2 2 0 0 0-2.9-2.9l-2.2 2.2zM14.5 17.5l-2.2 2.2a4.6 4.6 0 0 1-6.5-6.5L8 11l1.8 1.8-2.2 2.2a2 2 0 0 0 2.9 2.9l2.2-2.2z"/><path d="M8.3 14l5.7-5.7 1.7 1.7-5.7 5.7z"/>',
	"sack":'<path d="M9 2h6l-1.6 3.4c4.5 1.6 7.6 5.6 7.6 10.1 0 4.2-3.6 6.5-9 6.5s-9-2.3-9-6.5C3 11 6.1 7 10.6 5.4z"/>',
	"hand":'<path d="M8 11V4.5a1.5 1.5 0 0 1 3 0V10h.6V3a1.5 1.5 0 0 1 3 0v7h.6V4.5a1.5 1.5 0 0 1 3 0V11h.5V7.5a1.5 1.5 0 0 1 3 0V14c0 4.4-3.3 8-8 8-3.3 0-5.4-1.6-7-4.2L3 13.7c-.6-1 .1-2.2 1.2-2.2.6 0 1.1.3 1.5.8L8 15z"/>',
	# 種族の系統
	"goblin":'<path d="M12 5c3.3 0 6 2.2 6.6 5.2L23 7.5l-2.3 6.6c-.6 4.2-4.2 7.4-8.7 7.4s-8.1-3.2-8.7-7.4L1 7.5l4.4 2.7C6 7.2 8.7 5 12 5z"/><circle cx="9" cy="13" r="1.5" fill="#000" fill-opacity=".55"/><circle cx="15" cy="13" r="1.5" fill="#000" fill-opacity=".55"/>',
	"orc":'<path d="M12 3c4.4 0 8 3.4 8 8.2V15c0 3.9-3.6 7-8 7s-8-3.1-8-7v-3.8C4 6.4 7.6 3 12 3z"/><path d="M7.5 15.5 8.5 11l1.5 4.5zM16.5 15.5 15.5 11 14 15.5z" fill="#000" fill-opacity=".5"/><circle cx="9" cy="10" r="1.3" fill="#000" fill-opacity=".55"/><circle cx="15" cy="10" r="1.3" fill="#000" fill-opacity=".55"/>',
	"spider":'<ellipse cx="12" cy="14" rx="4.5" ry="5.5"/><circle cx="12" cy="7" r="3"/><path d="M8 11 2 7l-.8 1.2 6 4.4zM8 14l-6.5 1.2.3 1.4 6.4-1zM8.3 16.8 3 21.2l1 1 5.3-4zM16 11l6-4 .8 1.2-6 4.4zM16 14l6.5 1.2-.3 1.4-6.4-1zM15.7 16.8 21 21.2l-1 1-5.3-4z"/>',
	"bull":'<path d="M12 7c3.3 0 5.5 2.4 5.5 5.5 0 2-.8 3.5-1.5 5l-1 3.5H9l-1-3.5c-.7-1.5-1.5-3-1.5-5C6.5 9.4 8.7 7 12 7z"/><path d="M6.5 9.5C3.5 9 1.5 6.8 1.5 3.5c1.2 1.8 3 2.7 6 3zM17.5 9.5c3-.5 5-2.7 5-6-1.2 1.8-3 2.7-6 3z"/><circle cx="10" cy="12" r="1.2" fill="#000" fill-opacity=".55"/><circle cx="14" cy="12" r="1.2" fill="#000" fill-opacity=".55"/>',
	"demon":'<path d="M12 6c3.6 0 6.5 2.9 6.5 6.8S15.6 21 12 21s-6.5-4.3-6.5-8.2S8.4 6 12 6z"/><path d="M6.6 8.8C5 7 4.5 4.6 5.2 2c.8 2 2.3 3.4 4 4zM17.4 8.8C19 7 19.5 4.6 18.8 2c-.8 2-2.3 3.4-4 4z"/><path d="M9 12.5l2 1-2 .8zM15 12.5l-2 1 2 .8z" fill="#000" fill-opacity=".55"/>',
	"angel":'<path fill-rule="evenodd" d="M12 1.5c3 0 5 .8 5 1.9s-2 1.9-5 1.9-5-.8-5-1.9 2-1.9 5-1.9zm0 1.1c-2 0-3.2.4-3.2.8s1.2.8 3.2.8 3.2-.4 3.2-.8-1.2-.8-3.2-.8z"/><circle cx="12" cy="9" r="3"/><path d="M12 13c2 0 3 1.5 3.3 3.5L16 22H8l.7-5.5C9 14.5 10 13 12 13zM9.5 13.5C6 13 3 10.5 1.5 7c1.5 5 1.8 9 6.5 11.5zM14.5 13.5c3.5-.5 6.5-3 8-6.5-1.5 5-1.8 9-6.5 11.5z"/>',
	"bat":'<path d="M12 8.5c1.2 0 2 .8 2 2.2l1.5-1.2c1.8 1.7 4.4 1.4 7.5-.5-.6 3-2 4.8-4 5.8.1 1.5-.4 2.7-1.3 3.7-1-1-2.3-1.4-3.7-1.2l-2 2.5-2-2.5c-1.4-.2-2.7.2-3.7 1.2-.9-1-1.4-2.2-1.3-3.7-2-1-3.4-2.8-4-5.8 3.1 1.9 5.7 2.2 7.5.5L10 10.7c0-1.4.8-2.2 2-2.2z"/>',
	"snake":'<path d="M17 3c2.8 0 4.5 1.8 4.5 4 0 2.6-2.2 4-5.3 4H8.5c-1.4 0-2.2.7-2.2 1.7s.8 1.8 2.2 1.8H15c3.4 0 5.5 1.7 5.5 4.2S18.4 22.5 15 22.5H3v-2.6h12c1.6 0 2.7-.6 2.7-1.6s-1.1-1.6-2.7-1.6H8.5C5.3 16.7 3.5 15 3.5 12.7S5.3 8.5 8.5 8.5h7.7c1.5 0 2.5-.5 2.5-1.5S17.8 5.5 17 5.5h-2.5V3z"/>',
	"slime":'<path d="M12 4c2 3 8.5 7.5 8.5 12 0 3.4-3.8 5.5-8.5 5.5S3.5 19.4 3.5 16C3.5 11.5 10 7 12 4z"/><circle cx="9.3" cy="14.5" r="1.4" fill="#000" fill-opacity=".5"/><circle cx="14.7" cy="14.5" r="1.4" fill="#000" fill-opacity=".5"/>',
	"moth":'<path d="M12 6.5c.8 0 1.2.8 1.2 2V19c0 1-.5 1.5-1.2 1.5s-1.2-.5-1.2-1.5V8.5c0-1.2.4-2 1.2-2z"/><path d="M11 9C8 4.5 3.5 3.5 1.5 5c0 4 2.5 7 6 7.6-2.5 1-4 3-4.3 6 3 .5 6-1.5 7.8-5zM13 9c3-4.5 7.5-5.5 9.5-4 0 4-2.5 7-6 7.6 2.5 1 4 3 4.3 6-3 .5-6-1.5-7.8-5z"/>',
	"tentacle":'<path d="M5 22c0-6 2-9.5 4.5-12.5C11.3 7.3 12 5.5 11 3.5c3 .7 4.5 3.4 3.5 6.5-.9 2.7-3.3 5-3.8 8.2-.3 1.7.3 3 1.6 3.8z"/><path d="M13.5 22c1-4 3.5-6 5.5-8.5 1.3-1.6 1.5-3.2.8-4.8 2.5 1 3.4 3.7 2.2 6.2-1.2 2.5-4 4.3-5 7.1z"/>',
	# ほか
	"star":'<path d="M12 2l2.9 6.3 6.9.8-5.1 4.7 1.4 6.8L12 17.2l-6.1 3.4 1.4-6.8L2.2 9.1l6.9-.8z"/>',
	"arrow":'<path d="M3 10.5h12.5L11 6l2.1-2.1L21.2 12l-8.1 8.1L11 18l4.5-4.5H3z"/>',
	"pencil":'<path d="M15.5 3.5l5 5L9 20H4v-5zM13.5 5.5l5 5"/>',
	"bag":'<path d="M8 7V6a4 4 0 0 1 8 0v1h3.5l1 15h-17l1-15zm2 0h4V6a2 2 0 0 0-4 0z"/>',
	"back":'<path d="M15.5 3.5 17.6 5.6 11.2 12l6.4 6.4-2.1 2.1L7 12z"/>',
	"close":'<path d="M5.6 3.5 12 9.9l6.4-6.4 2.1 2.1L14.1 12l6.4 6.4-2.1 2.1L12 14.1l-6.4 6.4-2.1-2.1L9.9 12 3.5 5.6z"/>',
	"bolt":'<path d="M13.5 1.5 4 13.5h6.5l-1.5 9 10-12.5h-6.5z"/>',
	"aura":'<path fill-rule="evenodd" d="M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zm0 2.4a6.6 6.6 0 1 0 0 13.2 6.6 6.6 0 0 0 0-13.2z"/><circle cx="12" cy="12" r="3.5"/>',
	"tree":'<circle cx="12" cy="4.5" r="2.5"/><circle cx="5" cy="18.5" r="2.5"/><circle cx="12" cy="18.5" r="2.5"/><circle cx="19" cy="18.5" r="2.5"/><path d="M11 6.5h2v4.5h6.9v5.2h-2v-3.2H13v3.2h-2v-3.2H6.1v3.2h-2v-5.2H11z"/>',
	"paw":'<ellipse cx="12" cy="16" rx="5.2" ry="4.5"/><ellipse cx="6" cy="10" rx="2" ry="2.6"/><ellipse cx="18" cy="10" rx="2" ry="2.6"/><ellipse cx="9.3" cy="5.8" rx="2" ry="2.6"/><ellipse cx="14.7" cy="5.8" rx="2" ry="2.6"/>',
	"lock":'<path d="M7 10V7.5a5 5 0 0 1 10 0V10h1.5v11.5h-13V10zm2.4 0h5.2V7.5a2.6 2.6 0 0 0-5.2 0z"/>',
	"crown":'<path d="M2.5 7.5 7.5 11 12 3.5 16.5 11l5-3.5-2 11h-15zM4.5 20h15v2h-15z"/>',
	"sort":'<path d="M7 3 11.5 8H8.5v13h-3V8H2.5zM17 21l-4.5-5h3V3h3v13h3z"/>',
	"filter":'<path d="M2.5 4h19l-7.5 9v7l-4 2v-9z"/>',
	"gear":'<path fill-rule="evenodd" d="M10.3 1.5h3.4l.6 2.9 1.8.8 2.5-1.6 2.4 2.4-1.6 2.5.8 1.8 2.9.6v3.4l-2.9.6-.8 1.8 1.6 2.5-2.4 2.4-2.5-1.6-1.8.8-.6 2.9h-3.4l-.6-2.9-1.8-.8-2.5 1.6-2.4-2.4 1.6-2.5-.8-1.8-2.9-.6v-3.4l2.9-.6.8-1.8-1.6-2.5 2.4-2.4 2.5 1.6 1.8-.8zM12 8.2a3.8 3.8 0 1 0 0 7.6 3.8 3.8 0 0 0 0-7.6z"/>',
	"door":'<path d="M5 2h11v2H7v16h9v2H5z"/><path d="M9 3.5 19 2v20L9 20.5z"/><circle cx="16" cy="12" r="1.1" fill="#000" fill-opacity=".5"/>',
	"play":'<path d="M6 3.5 20 12 6 20.5z"/>',
	"skull":'<path fill-rule="evenodd" d="M12 2c5 0 8.5 3.4 8.5 8.2 0 2.7-1.2 4.6-3 5.8V20h-2.2v-2h-1.8v2h-3v-2H8.7v2H6.5v-4C4.7 14.8 3.5 12.9 3.5 10.2 3.5 5.4 7 2 12 2zM8.5 9a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm7 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM12 13l-1.2 2.4h2.4z"/>',
	"castle":'<path d="M2 22V8h3v2h2V8h3v3h4V8h3v2h2V8h3v14h-8v-5a2 2 0 0 0-4 0v5z"/><path d="M4 4h2V2h1v2h1v4H4zM16 4h2V2h1v2h1v4h-4z"/>',
	"flag":'<path d="M5 2h2v20H5z"/><path d="M8 3h12l-3 4.5L20 12H8z"/>',
	"hourglass":'<path d="M5 2h14v2h-1.5c0 3.5-2 5.8-4 8 2 2.2 4 4.5 4 8H19v2H5v-2h1.5c0-3.5 2-5.8 4-8-2-2.2-4-4.5-4-8H5zm4 2c0 2.5 1.4 4.3 3 6 1.6-1.7 3-3.5 3-6z"/>',
	"eye":'<path fill-rule="evenodd" d="M12 5c5 0 8.8 3.4 10.5 7-1.7 3.6-5.5 7-10.5 7S3.2 15.6 1.5 12C3.2 8.4 7 5 12 5zm0 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8z"/><circle cx="12" cy="12" r="1.8"/>',
	"hammer":'<path d="M3 7.5 9.5 1l3.2 3.2-1.5 1.5 1.8 1.8L20.5 15l-3 3-7.5-7.5-1.8-1.8-1.5 1.5z"/><path d="M11.5 13.5l2.8 2.8-5.8 5.8-2.8-2.8z"/>',
	"book":'<path d="M4 3.5h6c1.1 0 2 .6 2 1.5 0-.9.9-1.5 2-1.5h6V19h-6c-1.1 0-2 .7-2 1.5 0-.8-.9-1.5-2-1.5H4z"/><path d="M11.3 5.5h1.4v14h-1.4z" fill="#000" fill-opacity=".45"/>',
	"map":'<path d="M2 5.5 8 3l8 2.5L22 3v15.5L16 21l-8-2.5L2 21z"/><path d="M7.3 3.3h1.4v15.4H7.3zM15.3 5.3h1.4v15.4h-1.4z" fill="#000" fill-opacity=".4"/>',
	"moon":'<path d="M15 2.5a9.5 9.5 0 1 0 6.5 16.4A8 8 0 0 1 15 2.5z"/><circle cx="18" cy="6" r="1.2"/><circle cx="21" cy="10" r=".8"/>',
	"cage":'<path d="M4 7c0-2.8 3.6-5 8-5s8 2.2 8 5v14.5H4zM6.5 8v11h1.8V8zm4.6 0v11h1.8V8zm4.6 0v11h1.8V8z"/><path d="M11 .5h2v2h-2z"/>',
	"bed":'<path d="M2 6h2.5v7h17V21H19v-2.5H5V21H2z"/><circle cx="8" cy="10" r="2.2"/><path d="M11.5 8h7c1.7 0 3 1.3 3 3v1h-10z"/>',
	"flame":'<path d="M12 1.5c1 4 5.5 6.5 5.5 12.2A5.6 5.6 0 0 1 12 22a5.6 5.6 0 0 1-5.5-8.3c.8-1.9 2-2.7 2.3-4.9 1.4 1.1 1.8 2.6 1.8 4 1.8-2.6 1.9-7.3 1.4-11.3z"/>',
	"scroll":'<path d="M6 3h13a2.5 2.5 0 0 1 0 5h-1v11.5A2.5 2.5 0 0 1 15.5 22H4.5a2.5 2.5 0 0 1 0-5H6zM8.5 7h7M8.5 11h7M8.5 15h5" /><path d="M8 6.2h8v1.6H8zM8 10.2h8v1.6H8zM8 14.2h6v1.6H8z" fill="#000" fill-opacity=".45"/>',
	"egg":'<path d="M12 2c3.8 0 7 6 7 11.5A7 7 0 0 1 5 13.5C5 8 8.2 2 12 2z"/>',
	"plus":'<path d="M10.5 3h3v7.5H21v3h-7.5V21h-3v-7.5H3v-3h7.5z"/>',
	"bin":'<path d="M3.5 5.5h17v2.5h-17zM9 2.5h6v2H9z"/><path d="M5.5 9.5h13l-1.4 12H6.9z"/><path d="M8.6 11.5h1.4l.4 8H9zM13.6 11.5H15l-.4 8h-1.4z" fill="#000" fill-opacity=".45"/>',
}
## 種族 → 系統の記号。
const SPECIES:={
	"goblin":"goblin","hobgoblin":"goblin","goblin_binder":"goblin","goblin_shaman":"goblin",
	"orc":"orc","orc_chief":"orc","siege_orc":"orc","berserker_orc":"orc","iron_orc":"orc",
	"spider":"spider","jorougumo":"spider","venom_spider":"spider",
	"minotaur":"bull","minotaur_lord":"bull","incubus":"demon","incubus_lord":"demon","fallen_angel":"angel",
	"dark_elf":"bow","shadow_archer":"bow","bat":"bat","serpent":"snake","sea_serpent":"snake",
	"slime":"slime","moth":"moth","tentacle":"tentacle",
}
const ROLE:={"tank":"shield","swarm":"group","flying":"wing","ranged":"bow","caster":"staff","capture":"hand","binder":"chain","carrier":"sack"}
const STAT:={"str":"sword","mag":"magic","spd":"wing","end":"shield"}
const SLOT:={"weapon":"sword","armor":"armor","trinket":"ring"}
## 部屋の記号（部屋の ID で決まっていれば優先、無ければ種類から）。
const ROOM_KIND:={"hold":"cage","train":"chain","breed":"heart","work":"hammer","rest":"bed","military":"sword"}
const ROOM:={"altar":"magic","den":"paw","library":"book","smithy":"hammer","infirmary":"bed","drill":"target","nursery":"egg","trash":"bin","prison":"cage","wall":"castle","milking":"drop","horse":"chain","mat":"crown","stand":"eye","post":"heart","table":"chain"}

static func room(id: String,kind: String) -> String:
	return str(ROOM.get(id,ROOM_KIND.get(kind,"paw")))
static var cache: Dictionary={}

## 記号の画像（白）。px は表示の大きさ（画面の拡大に合わせて2倍で作る）。
static func tex(name: String,px: int=24) -> Texture2D:
	var key: String="%s@%d"%[name,px]
	if cache.has(key):return cache[key]
	var body: String=str(SVG.get(name,SVG.paw))
	var svg: String='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#fff">%s</svg>'%body
	var img:=Image.new()
	var err: int=img.load_svg_from_string(svg,float(px)*2.0/24.0)
	if err!=OK:return null
	img.generate_mipmaps()
	var t:=ImageTexture.create_from_image(img)
	cache[key]=t
	return t

static func rect(name: String,px: int=24,color: Color=Color.WHITE) -> TextureRect:
	var r:=TextureRect.new()
	r.texture=tex(name,px)
	r.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size=Vector2(px,px)
	r.modulate=color
	r.mouse_filter=Control.MOUSE_FILTER_IGNORE
	r.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r

static func species(sp: String) -> String:
	return str(SPECIES.get(sp,"paw"))

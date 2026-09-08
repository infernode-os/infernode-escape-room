implement SsePauseSoak;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llmclient.m";
	llmclient: Llmclient;
	AskRequest, AskResponse: import llmclient;

SsePauseSoak: module
{
	PATH: con "/dis/tests/escape-sse-pause-soak.dis";
	init: fn(nil: ref Draw->Context, args: list of string);
};

memory(label: string, events: int)
{
	fd := sys->open("/dev/memory", Sys->OREAD);
	if(fd == nil) {
		sys->print("@@SOAK memory-error label=%s events=%d err=%r\n", label, events);
		return;
	}
	buf := array[1024] of byte;
	n := sys->read(fd, buf, len buf);
	sys->print("@@SOAK memory label=%s events=%d\n", label, events);
	if(n > 0)
		sys->print("%s", string buf[0:n]);
	sys->print("@@SOAK memory-end\n");
}

mockserver(port: string, events, delayms, sampleevery: int, ready, done: chan of int)
{
	(ok, c) := sys->announce("tcp!127.0.0.1!" + port);
	if(ok < 0) { ready <-= -1; done <-= -1; return; }
	ready <-= 1;
	(lok, lc) := sys->listen(c);
	if(lok < 0) { done <-= -1; return; }
	fd := sys->open(lc.dir + "/data", Sys->ORDWR);
	if(fd == nil) { done <-= -1; return; }
	buf := array[8192] of byte;
	if(sys->read(fd, buf, len buf) < 0) { done <-= -1; return; }
	header := array of byte "HTTP/1.0 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n";
	if(sys->write(fd, header, len header) != len header) { done <-= -1; return; }
	heartbeat := array of byte ": escape-room quota paused\n\n";
	for(i := 1; i <= events; i++) {
		if(sys->write(fd, heartbeat, len heartbeat) != len heartbeat) {
			done <-= -1;
			return;
		}
		if(sampleevery > 0 && i % sampleevery == 0)
			memory("streaming", i);
		if(delayms > 0)
			sys->sleep(delayms);
	}
	final := array of byte "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}],\"usage\":{\"total_tokens\":1}}\n\ndata: [DONE]\n\n";
	if(sys->write(fd, final, len final) != len final) { done <-= -1; return; }
	fd = nil;
	done <-= 1;
}

request(): ref AskRequest
{
	r := ref AskRequest;
	r.model = "soak";
	r.temperature = 0.0;
	r.systemprompt = "local deterministic SSE soak";
	r.prompt = "respond ok";
	r.streamch = chan[1] of string;
	return r;
}

contains(haystack, needle: string): int
{
	if(len needle == 0)
		return 1;
	for(i := 0; i + len needle <= len haystack; i++)
		if(haystack[i:i + len needle] == needle)
			return 1;
	return 0;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	llmclient = load Llmclient Llmclient->PATH;
	if(llmclient == nil)
		raise "fail:cannot load llmclient";
	llmclient->init();

	events := 10000;
	delayms := 1;
	sampleevery := 1000;
	if(args != nil)
		args = tl args;
	if(args != nil) { events = int hd args; args = tl args; }
	if(args != nil) { delayms = int hd args; args = tl args; }
	if(args != nil) { sampleevery = int hd args; }
	if(events <= 0 || delayms < 0 || sampleevery <= 0)
		raise "fail:invalid arguments";

	memory("start", 0);
	ready := chan[1] of int;
	done := chan[1] of int;
	spawn mockserver("29995", events, delayms, sampleevery, ready, done);
	if(<-ready < 0)
		raise "fail:mock server";
	(resp, err) := llmclient->askopenai("http://127.0.0.1:29995/v1", "", request());
	serverok := <-done;
	memory("finish", events);
	if(serverok < 0 || err != nil || resp == nil || !contains(resp.response, "ok"))
		raise sys->sprint("fail:soak response server=%d err=%s", serverok, err);
	sys->print("@@SOAK PASS events=%d delay_ms=%d sample_every=%d\n",
		events, delayms, sampleevery);
}

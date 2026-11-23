# arch-viewer prototype

This is throwaway code. It answers one question: how does an interactive
architecture viewer for a Rails app look and feel?

Open `index.html` in a browser. Use the bottom bar or the ← → keys to change
the variant. The URL keeps the state (`?variant=A&diagram=real&colour=cc&drill=models&select=Message`).

| Variant | Name | Verdict |
|---|---|---|
| A | Drill-down boxes (uml-viewer style) | Keep |
| B | Layer bands, every class on one screen | Keep |
| C | Dependency matrix | Drop |

The data is a real scan of [Campfire](https://github.com/basecamp/once-campfire)
(Basecamp, MIT licence, commit `945c22f`, November 2026): 136 classes, 221 links.
The scan has no coverage and no mutation data. The class card shows Campfire's
source, under its MIT licence.

## Files

- `scan.rb`: reads `app/**/*.rb` with Prism. It writes the classes, the methods
  (with a rough complexity), the constant references and the associations as JSON.
- `churn.txt`: the number of git commits for each file.
- `ir.json`: the scan with the churn added.
- `template.html`: the viewer. It has no dependencies.
- `build.rb`: puts `ir.json` into `template.html` and writes `index.html`.
- `screenshots/`: the variants as headless Chromium shows them.

## Make it again for an app

```bash
git clone --filter=blob:none https://github.com/basecamp/once-campfire.git /tmp/once-campfire
APP=/tmp/once-campfire
ruby -rtime scan.rb $APP > ir.json
git -C $APP log --format= --name-only -- app | grep '\.rb$' | sort | uniq -c > churn.txt
ruby -rjson -e 'ch={}; File.foreach("churn.txt"){|l| n,f=l.split; ch[f]=n.to_i}
  d=JSON.parse(File.read("ir.json")); d["classes"].each{|c| c["churn"]=ch[c["file"]]||0}
  File.write("ir.json", JSON.generate(d))'
ruby build.rb
```

The real diagram levels are generic Rails folders (`REAL_LEVELS`). The two
proposals are hard-coded for Campfire in `template.html` (`DIAGRAMS`).

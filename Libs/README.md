# Bundled libraries

Goblinomics vendors its libraries instead of using `.pkgmeta` `externals`, so a
symlinked checkout loads in the client without a packager run and busted can use
LibDeflate/LibSerialize offline. Only the core addon loads them; modules get them
through LibStub.

| Library | Version | Copied from (2026-09-24) | Licence | Upstream |
| --- | --- | --- | --- | --- |
| LibStub | minor 2 | Auctionator 169 | public domain (file header) | https://www.wowace.com/projects/libstub |
| CallbackHandler-1.0 | minor 8 | BigWigs | see upstream | https://www.wowace.com/projects/callbackhandler |
| LibDataBroker-1.1 | minor 4 | BugSack | see upstream | https://github.com/tekkub/libdatabroker-1-1 |
| LibDBIcon-1.0 | minor 56 | BugSack | All Rights Reserved, made for embedding (upstream TOC) | https://www.wowace.com/projects/libdbicon-1-0 |
| LibSharedMedia-3.0 | 12000002 | BugSack | LGPL 2.1 (file header) | https://www.wowace.com/projects/libsharedmedia-3-0 |
| LibDeflate | 1.0.2-release (minor 3) | TradeSkillMaster v336 | zlib (`LICENSE.txt`) | https://github.com/SafeteeWoW/LibDeflate |
| LibSerialize | minor 4 | TradeSkillMaster v336 | MIT (`LICENSE`) | https://github.com/rossnichols/LibSerialize |

Each library keeps its own licence; the MIT licence of Goblinomics does not
cover them. Update procedure: replace the `.lua` file, bump the row above, run `tools/test.sh`.
Only the `.lua` files are bundled; `lib.xml` wrappers are not needed because the
core TOC lists each file directly.

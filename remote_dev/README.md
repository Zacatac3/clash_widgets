# Development remote content

This folder uses the same schema and layout as `remote/`:

- `latest_event.json`: event definitions
- `latest_news.json`: newest news ID
- `news_feed.json`: news articles
- `images/`: development artwork
- `examples/`: payload templates

Edit these files, validate with `python3 tools/validate_remote_content.py remote_dev`, then commit and push. In the updated app, open Settings → Debug → **Grab Remote Dev Files**. This switches only that installation to `remote_dev` and downloads all three feeds immediately. **Grab Remote Files Now** switches back to `remote`.

The selection survives app restarts. Live is the default. Cache, refresh timestamps and news-read state are separate, and development event identities are namespaced internally. The app shows Development Feed Active on Home.

Use disposable profiles for timer tests: applied reductions remain on tracked upgrades even after switching back to Live. The synthetic Event Test profile can be used for downloaded dev events; its local five-minute event is paused while Development is selected.

This folder initially mirrors the current test feeds with DEV titles and its own builder icon URL. Dates are fixed, so update them before future tests. Changing files here does not publish an event to users of the live feed.

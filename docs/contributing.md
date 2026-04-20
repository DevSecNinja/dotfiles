# 🤝 Contributing

Contributions, forks, and adaptations are welcome. The full
[`CONTRIBUTING.md`](https://github.com/DevSecNinja/dotfiles/blob/main/CONTRIBUTING.md)
in the repository has the canonical guide; the sections below summarise
the key workflows.

## Local Development

1. **Edit files in the repository** (not in your home directory):

    ```bash
    cd /path/to/dotfiles
    vim home/dot_config/fish/config.fish
    ```

2. **Test your changes** with a dry run, then apply locally:

    ```bash
    chezmoi apply --dry-run --source=.
    chezmoi apply --source=.
    ```

3. **Verify everything still works**:

    ```bash
    chezmoi verify
    ```

## Validate Before Committing

Install Python dependencies, then run all validation:

```bash
pip3 install -r requirements.txt
./tests/bash/run-tests.sh --ci
pre-commit run --all-files
```

All three commands should succeed before opening a pull request.

## Editing the Documentation

The documentation you are reading lives in the `docs/` directory and is
built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/).

To preview the docs locally:

```bash
pip install mkdocs-material
mkdocs serve
```

Open <http://127.0.0.1:8000/> in your browser. Changes to files in
`docs/` or to `mkdocs.yml` trigger an automatic reload.

To produce a production build (used by CI):

```bash
mkdocs build --strict
```

The built site is written to `site/` (which is git-ignored). On every
push to `main`, CI builds the documentation and deploys it to GitHub
Pages at [dotfiles.ravensberg.org](https://dotfiles.ravensberg.org/).

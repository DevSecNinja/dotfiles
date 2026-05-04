# Changelog

All notable changes to this project will be documented in this file.

## [0.3.0](https://github.com/DevSecNinja/dotfiles/compare/v0.2.2...v0.3.0) (2026-05-04)


### Features

* **yubikey:** add SSH helpers, clipboard-copy and useYubiKey toggle ([#280](https://github.com/DevSecNinja/dotfiles/issues/280)) ([e26cf66](https://github.com/DevSecNinja/dotfiles/commit/e26cf6640900bbacf743b93a1079cb0725f1844d))
* **yubikey:** add yk-ssh-copy-id helper ([#305](https://github.com/DevSecNinja/dotfiles/issues/305)) ([dedaa2a](https://github.com/DevSecNinja/dotfiles/commit/dedaa2a9e08faaadd2a38ac42ef76aefef9c2f9a))
* **yubikey:** auto-install ykman via packages.yaml when useYubiKey is true ([#286](https://github.com/DevSecNinja/dotfiles/issues/286)) ([222e450](https://github.com/DevSecNinja/dotfiles/commit/222e450a04ed2662a24bef472b28a7245e715ad9))
* **yubikey:** idempotent enrollment wizard (`yk-enroll`) ([#293](https://github.com/DevSecNinja/dotfiles/issues/293)) ([8966c94](https://github.com/DevSecNinja/dotfiles/commit/8966c9468cd1fdb5bfedf6fb5f3ea10c64b1667e))
* **yubikey:** SSH-based git commit signing (per-serial + signing-key upload mandatory) ([#282](https://github.com/DevSecNinja/dotfiles/issues/282)) ([b3e7fee](https://github.com/DevSecNinja/dotfiles/commit/b3e7feef942cd92c2b59bd1db5d1f7f4ff80f1c6))
* **yubikey:** yk-status health checks; pubkey per-serial; remove yk-ssh-load ([#303](https://github.com/DevSecNinja/dotfiles/issues/303)) ([8c5dc13](https://github.com/DevSecNinja/dotfiles/commit/8c5dc13de4d39ec75fea0b0403dd23b4f8ad387e))


### Bug Fixes

* **github-release:** update release jdx/mise ( v2026.4.17 ➔ v2026.4.18 ) ([#277](https://github.com/DevSecNinja/dotfiles/issues/277)) ([71889c5](https://github.com/DevSecNinja/dotfiles/commit/71889c5f975a45e161b49c8216c3f5bbd0f3864a))
* **yubikey:** detect modern ykman PIN status format ([#300](https://github.com/DevSecNinja/dotfiles/issues/300)) ([631fef1](https://github.com/DevSecNinja/dotfiles/commit/631fef19f0377c470d0ccc182fc2c607ba149593))
* **yubikey:** don't lie about ykman PIN-rotation prompt order ([#296](https://github.com/DevSecNinja/dotfiles/issues/296)) ([f9520ae](https://github.com/DevSecNinja/dotfiles/commit/f9520ae590de0310b212b0f65bd4112c15e506d1))
* **yubikey:** drop `AddKeysToAgent` — `ssh-agent` can't re-prompt for the FIDO2 PIN ([#302](https://github.com/DevSecNinja/dotfiles/issues/302)) ([9eb385e](https://github.com/DevSecNinja/dotfiles/commit/9eb385e6bdb08d9aca324499e9766bdc5fbe44b4))
* **yubikey:** drop hostname from suggested GitHub-key title ([#301](https://github.com/DevSecNinja/dotfiles/issues/301)) ([c526c9d](https://github.com/DevSecNinja/dotfiles/commit/c526c9d90f5c2348c7a3013d162095dede99b7cd))
* **yubikey:** keep 1Password SSH fallback until FIDO2 keys exist ([#288](https://github.com/DevSecNinja/dotfiles/issues/288)) ([26ba093](https://github.com/DevSecNinja/dotfiles/commit/26ba0931bd82e593e2d7c2cf9818e098c23ee769))
* **yubikey:** polish enrollment UX — no duplicate footer, useful title, auto-load via SSH config ([#298](https://github.com/DevSecNinja/dotfiles/issues/298)) ([82ecb92](https://github.com/DevSecNinja/dotfiles/commit/82ecb9298aeeb953b8b37a12e2e08ced683cf696))
* **yubikey:** verify enrollment + FIPS PIN handling + work-checklist ([#295](https://github.com/DevSecNinja/dotfiles/issues/295)) ([8ae532c](https://github.com/DevSecNinja/dotfiles/commit/8ae532c0e2a96afb999b00a3e0c2ab6521e8b77c))
* **yubikey:** vertical yk-status, pubkey zsh nomatch, GitHub UI link, drop stale yk-ssh-load files ([#304](https://github.com/DevSecNinja/dotfiles/issues/304)) ([82956c1](https://github.com/DevSecNinja/dotfiles/commit/82956c17277a0faf0969df7649db5880bb29c37f))
* **yubikey:** yk-git-sign-setup must not write self-keys to allowed_signers (chezmoi drift) ([#306](https://github.com/DevSecNinja/dotfiles/issues/306)) ([19c2d7b](https://github.com/DevSecNinja/dotfiles/commit/19c2d7b32fa04c1596ddfb61eeb854511c77e33c))
* **yubikey:** zsh leak in `yk-status`, device type, clearer macOS FIDO2 error ([#290](https://github.com/DevSecNinja/dotfiles/issues/290)) ([5bf62c2](https://github.com/DevSecNinja/dotfiles/commit/5bf62c2c03ad57ea48f59adc88533c99a3d3023c))

## [0.2.2](https://github.com/DevSecNinja/dotfiles/compare/v0.2.1...v0.2.2) (2026-05-03)


### ⚠ BREAKING CHANGES

* **github-action:** Update action jdx/mise-action ( v2 ➔ v4.0.1 ) ([#247](https://github.com/DevSecNinja/dotfiles/issues/247))

### Features

* **harden-runner:** harden GitHub Actions jobs ([#271](https://github.com/DevSecNinja/dotfiles/issues/271)) ([5506be1](https://github.com/DevSecNinja/dotfiles/commit/5506be11c2a37899961ca421735bcf4782450fbc))


### Miscellaneous Chores

* release 0.2.2 ([8789d6a](https://github.com/DevSecNinja/dotfiles/commit/8789d6ab70364bcaa1345a5c6ecf29a0a761322a))


### Continuous Integration

* **github-action:** Update action jdx/mise-action ( v2 ➔ v4.0.1 ) ([#247](https://github.com/DevSecNinja/dotfiles/issues/247)) ([464e45a](https://github.com/DevSecNinja/dotfiles/commit/464e45af47193e66f1e53db43dd433a412f83956))

## [0.2.1](https://github.com/DevSecNinja/dotfiles/compare/v0.2.0...v0.2.1) (2026-05-02)


### Bug Fixes

* **github-release:** update release jdx/mise ( v2026.4.16 ➔ v2026.4.17 ) ([#269](https://github.com/DevSecNinja/dotfiles/issues/269)) ([b2ebe8d](https://github.com/DevSecNinja/dotfiles/commit/b2ebe8d7cb3998dc7440f0cf1b1b59daae4981b6))
* **release:** notify IRM on workflow_dispatch reruns ([#265](https://github.com/DevSecNinja/dotfiles/issues/265)) ([573ffe5](https://github.com/DevSecNinja/dotfiles/commit/573ffe5f9f8745179778aa52bc3a7d21e806c849))
* **release:** trigger on tag push instead of release:created ([#263](https://github.com/DevSecNinja/dotfiles/issues/263)) ([e530803](https://github.com/DevSecNinja/dotfiles/commit/e530803f5c96b592512a55987a966f1f0aa4750d))

## [0.2.0](https://github.com/DevSecNinja/dotfiles/compare/v0.1.4...v0.2.0) (2026-05-01)


### Features

* add workflow_dispatch to sign-powershell.yml ([#256](https://github.com/DevSecNinja/dotfiles/issues/256)) ([11acaf7](https://github.com/DevSecNinja/dotfiles/commit/11acaf78d549ecf3870e0cba9f9262675eda13a5))
* **ci:** page Grafana IRM on main-branch workflow failures ([#255](https://github.com/DevSecNinja/dotfiles/issues/255)) ([8b48ad6](https://github.com/DevSecNinja/dotfiles/commit/8b48ad675b1a6cd402150b08ee0c5958186e6a57))
* **git:** add 'sco' alias for auto-stash checkout ([#252](https://github.com/DevSecNinja/dotfiles/issues/252)) ([b97e761](https://github.com/DevSecNinja/dotfiles/commit/b97e76143fc3ca52580900356ce2575bb3d2b240))
* **github-release:** update release twpayne/chezmoi ( 2.69.1 ➔ 2.70.2 ) ([#246](https://github.com/DevSecNinja/dotfiles/issues/246)) ([9b34099](https://github.com/DevSecNinja/dotfiles/commit/9b34099834aadb3ee2645503e85f147d3af07371))
* **release:** adopt release-please for branch-protection-respecting bumps ([8cea8cd](https://github.com/DevSecNinja/dotfiles/commit/8cea8cd1ea859f35133fa7eb2c967677268ac7a7))
* **release:** adopt release-please for branch-protection-respecting bumps ([3f23dd9](https://github.com/DevSecNinja/dotfiles/commit/3f23dd9b19ceb054159ef43f0939a2a92a103b6b))
* **windows:** untangle winget upgrade from chezmoi update ([#253](https://github.com/DevSecNinja/dotfiles/issues/253)) ([93a0605](https://github.com/DevSecNinja/dotfiles/commit/93a0605b4de54ef14a3874b6b4aa4b76fbccbfb0))


### Bug Fixes

* **github-release:** update release jdx/mise ( v2026.4.15 ➔ v2026.4.16 ) ([#262](https://github.com/DevSecNinja/dotfiles/issues/262)) ([a44a08d](https://github.com/DevSecNinja/dotfiles/commit/a44a08dd8b498c7bd266d47c452c9d7d42254ee2))
* **github-release:** update release jdx/mise ( v2026.4.9 ➔ v2026.4.15 ) ([#245](https://github.com/DevSecNinja/dotfiles/issues/245)) ([6620fa6](https://github.com/DevSecNinja/dotfiles/commit/6620fa6dffe0b448485850fd5adaf814e30bcd5e))
* **log:** color stderr writes when stdout is a pipe ([6aa47a4](https://github.com/DevSecNinja/dotfiles/commit/6aa47a4a07c74414841cd91ac3faa43636e411ee))
* **release:** adopt draft-publish flow so release-please can tag ([#261](https://github.com/DevSecNinja/dotfiles/issues/261)) ([b78025f](https://github.com/DevSecNinja/dotfiles/commit/b78025f83aef1aa0bf0191e90f81da8674f4182b))

## [0.1.4] - 2026-04-30

### Bug Fixes
- **release**: Repin release-publish action to merged main SHA ([`992c035`](https://github.com/DevSecNinja/dotfiles/commit/992c0353a5c7994d052eda367143d7c59375dafc))

### Refactoring
- **release**: Use central release-publish composite action ([`7e7bd25`](https://github.com/DevSecNinja/dotfiles/commit/7e7bd25a168da6a6c712f3bd7ad6c9e29b4e61ae))

## [0.1.3] - 2026-04-30

### Documentation
- **log**: Explain log_data and clarify helper selection ([`301cfba`](https://github.com/DevSecNinja/dotfiles/commit/301cfbaa1a06eba19969cd02c8d6edf7263f6c70))
- **skill**: Record release pipeline pitfalls from v0.1.0-v0.1.2 ([`3d1a23b`](https://github.com/DevSecNinja/dotfiles/commit/3d1a23b361e9293bfea885fe4a7d17c95f66237f))

### Miscellaneous
- **version**: V0.1.3 ([`88ace8b`](https://github.com/DevSecNinja/dotfiles/commit/88ace8b7ddaa919a84a64559b8eacbe2d7dc26e7))

## [0.1.2] - 2026-04-30

### Bug Fixes
- **release**: Build version manifests from rolling per-arch tags ([`c5d64e0`](https://github.com/DevSecNinja/dotfiles/commit/c5d64e0e2158602ae58b8e6a98f1e4677f756876))

### Miscellaneous
- **version**: V0.1.2 ([`2b3a7d1`](https://github.com/DevSecNinja/dotfiles/commit/2b3a7d1723591a51ed126ca064eed98200b5ee94))

## [0.1.1] - 2026-04-30

### Bug Fixes
- **release**: Skip [skip ci] commits when checking gate status ([`f47f2dd`](https://github.com/DevSecNinja/dotfiles/commit/f47f2dd222fa385c1e74d58b9fd413d814ba3d17))

### CI/CD
- **release**: Publish release-pinned devcontainer image with attestation ([`880b0e5`](https://github.com/DevSecNinja/dotfiles/commit/880b0e5b2348cf582f07ac77062f5d3770808d21))

### Features
- **release**: Gate release:bump on green main CI ([`50552c2`](https://github.com/DevSecNinja/dotfiles/commit/50552c21916d41a28a2e724d9b44ccfbe6a70de5))

### Miscellaneous
- **version**: V0.1.1 ([`6bb6954`](https://github.com/DevSecNinja/dotfiles/commit/6bb6954ea235201fbcf6cd259eea76e42017ca4e))
- Trigger CI on f47f2dd ([`fa56afc`](https://github.com/DevSecNinja/dotfiles/commit/fa56afc459fda89463497eda2bacbe1decac44c5))
- Sign PowerShell scripts [skip ci] ([`41915a7`](https://github.com/DevSecNinja/dotfiles/commit/41915a70f243aac643f2e18fdfbfc88d7484a76c))

### Testing
- **powershell**: Align VS Code extension tests with empty common list ([`b0bc5c1`](https://github.com/DevSecNinja/dotfiles/commit/b0bc5c1ed3347a129f57e43762f77da47f440440))

## [0.1.0] - 2026-04-30

### Bug Fixes
- **scripts**: Skip PPA step on Debian; remove invalid gh telemetry call ([`875f99f`](https://github.com/DevSecNinja/dotfiles/commit/875f99f910987761429a2048ad1b253f0e5d56b1))
- **extensions**: Drop GitHub.copilot{,-chat} from common list ([`256eb69`](https://github.com/DevSecNinja/dotfiles/commit/256eb6955beecdbc74337b850836dcbf86700c76))
- **scripts**: Resolve lefthook via dotfiles cwd; surface code-cli errors ([`c68a94c`](https://github.com/DevSecNinja/dotfiles/commit/c68a94ceee72246c99eac28217bec283bd8406f8))
- Correct JSON quote escaping in _log_json_escape ([`73b2aa5`](https://github.com/DevSecNinja/dotfiles/commit/73b2aa5b72001d103ff55d6dc8f54621f0b6a079))
- Remove lefthook checks for non-PR events ([`003794e`](https://github.com/DevSecNinja/dotfiles/commit/003794ef568f72211c6a41d2c61934ca193622c1))
- Show successful lefthook shell checks ([`07742ce`](https://github.com/DevSecNinja/dotfiles/commit/07742ce7d28fd168ce40726848e22884f1460cea))
- Make password test tr shim POSIX-compatible ([`4f51bd7`](https://github.com/DevSecNinja/dotfiles/commit/4f51bd73e5c32a60e8b27823d211a3fc484645b3))
- Update bash tests for lefthook migration and deterministic passwords ([`65ebe44`](https://github.com/DevSecNinja/dotfiles/commit/65ebe4477d167ac1334da6b55cf60826e978cb58))
- Run generate-passwords in subshell with closed fds to break orphan pipeline ([`9579e32`](https://github.com/DevSecNinja/dotfiles/commit/9579e3237223640eb14b58f367ff6a81f8678835))
- Close bats fd 3 in generate-passwords tests to prevent CI hang ([`5c424eb`](https://github.com/DevSecNinja/dotfiles/commit/5c424eb836425217b5978ecab67c1290e59ccf7a))
- Isolate chezmoi state via separate HOME and --destination in dry-run test ([`7f58cde`](https://github.com/DevSecNinja/dotfiles/commit/7f58cde700d44b38aa6b51b1b898763a6720a934))
- Exclude chezmoi config dirs from dry-run file count test ([`faa0fc9`](https://github.com/DevSecNinja/dotfiles/commit/faa0fc9faffa5ff0763626b3424008dbd93f9f84))
- Update dot_gitmessage to follow conventional commits format ([`e10a8f8`](https://github.com/DevSecNinja/dotfiles/commit/e10a8f87e4f9cd4aaea38f62fe55fc74f5b21cff))
- Address code review feedback on mcd.fish and refreshenv.sh ([`6a21bfc`](https://github.com/DevSecNinja/dotfiles/commit/6a21bfc83669d0e155c129c8621b1ff94d917ca1))
- Optimize PowerShell profile startup to reduce loading time ([`a8da755`](https://github.com/DevSecNinja/dotfiles/commit/a8da75530dc1b61e99c9c322ecebaa6dba071cb0))
- **mise**: Update tool python ( 3.14.3 ➔ 3.14.4 ) ([`03934a1`](https://github.com/DevSecNinja/dotfiles/commit/03934a176c347c2a8e0ff063e87bf4be4ea74566))
- **pwsh**: Guard horizonfetch with a kill-on-timeout wrapper ([`a485ee0`](https://github.com/DevSecNinja/dotfiles/commit/a485ee08c5e5670567e2b9058c60e27c909436a3))
- Spacing in ssh config ([`99cb357`](https://github.com/DevSecNinja/dotfiles/commit/99cb3577707917c732859f0dc75d0bad971e6995))
- Unset CHEZMOI_GITHUB_USERNAME in setup to prevent interactive prompts ([`d31af0f`](https://github.com/DevSecNinja/dotfiles/commit/d31af0f13c1c17e7eef981ba58c86ee0b2bbe3d6))
- Remove report.xml and auto-install xmllint in CI ([`9309586`](https://github.com/DevSecNinja/dotfiles/commit/93095863862a20d18d64ea3cd837d815b482695b))
- Show real-time test progress in CI mode ([`7fa1f67`](https://github.com/DevSecNinja/dotfiles/commit/7fa1f67c4ba857fe946097c459b694e4df56ac61))
- Add pull-requests write permission for PR comments in sign-powershell workflow ([`e915733`](https://github.com/DevSecNinja/dotfiles/commit/e9157338b1ab8333b55c2e57120e25ab67cabb7b))
- Update Windows Terminal setup script messages and improve signing function to include repository root ([`a3661c9`](https://github.com/DevSecNinja/dotfiles/commit/a3661c9c0f163c015141716eb1b7f1b6921dd554))

### CI/CD
- Install Fish, Zsh, and Chezmoi so BATS validation tests don't skip ([`18adb46`](https://github.com/DevSecNinja/dotfiles/commit/18adb46a831bc868f85a20f7abae95cb2bdad793))
- **github-action**: Pin dependencies ([`efc2656`](https://github.com/DevSecNinja/dotfiles/commit/efc26565629932c27506e1f947335a0db2947900))
- **github-action**: Update action actions/github-script ( v8 ➔ v9 ) ([`58e7a94`](https://github.com/DevSecNinja/dotfiles/commit/58e7a9405cf5a8b1128bc439ac763ed4018bdc42))
- **github-action**: Pin dependencies ([`e01521f`](https://github.com/DevSecNinja/dotfiles/commit/e01521f85b565697160fdb7044915198a7e9191d))

### Dependencies
- **deps**: Update ghcr.io/devcontainers/features/powershell docker tag to v2 ([`e5a06c9`](https://github.com/DevSecNinja/dotfiles/commit/e5a06c9790616f89f42006239863eb87d2f9c046))
- **deps**: Update docker/setup-buildx-action action to v4 ([`61bd3bb`](https://github.com/DevSecNinja/dotfiles/commit/61bd3bb589482c96b47b9301351b769b0e35f19a))
- **deps**: Update docker/login-action action to v4 ([`98a8463`](https://github.com/DevSecNinja/dotfiles/commit/98a84631682a98ba1ebd8c28f6a5ee90283657b0))
- **deps**: Update actions/upload-artifact action to v7 ([`45b7888`](https://github.com/DevSecNinja/dotfiles/commit/45b78880420bc806b910129d82a3463230bf0115))
- **deps**: Update dependency python to v3.14.3 (#178) ([`4bd875f`](https://github.com/DevSecNinja/dotfiles/commit/4bd875f9d664641dc6c109e9e85a61981a446d47))
- **deps**: Update alstr/todo-to-issue-action digest to 64aca8f (#177) ([`018d078`](https://github.com/DevSecNinja/dotfiles/commit/018d0787169d90d1dcf1d8534282a97e6f8ff9d7))
- **deps**: Update actions/cache action to v5 ([`6880dbe`](https://github.com/DevSecNinja/dotfiles/commit/6880dbeab94033066d4ebe48b1e6ed409c6c95aa))
- **deps**: Update dependency python to v3.14.2 (#172) ([`37a9047`](https://github.com/DevSecNinja/dotfiles/commit/37a904739e44e828fc0db780620df16583d5ccaf))
- **deps**: Update actions/checkout action to v6.0.2 (#146) ([`eb662e9`](https://github.com/DevSecNinja/dotfiles/commit/eb662e9cb13d4911eee980ad7a61389a2f0fceda))
- **deps**: Update actions/upload-artifact action to v6 ([`fa0ee2d`](https://github.com/DevSecNinja/dotfiles/commit/fa0ee2d8563b550afeaabbd91255e841bcb7bb2b))
- **deps**: Update actions/checkout action to v6 ([`9179b7a`](https://github.com/DevSecNinja/dotfiles/commit/9179b7a65df5ae3e3623f7cf5f591660d7d3dc04))
- **deps**: Update actions/github-script action to v8 ([`5fad0e6`](https://github.com/DevSecNinja/dotfiles/commit/5fad0e6ae140485be0942126275f12f4537e5f0e))
- **deps**: Update actions/checkout action to v6 ([`12c8a01`](https://github.com/DevSecNinja/dotfiles/commit/12c8a0189061a2920fac99f5596a05dfbae629e2))
- **deps**: Update actions/setup-python action to v6 ([`6a9055f`](https://github.com/DevSecNinja/dotfiles/commit/6a9055fe3b27ca313aa8e7bf3f6c03533747b73f))

### Documentation
- **skill**: Document attestations and immutable releases ([`ada8c3f`](https://github.com/DevSecNinja/dotfiles/commit/ada8c3f50f365781c549a2ecf943c9f2810b3849))

### Features
- **release**: Single-shot release with build-provenance attestations ([`6a5884b`](https://github.com/DevSecNinja/dotfiles/commit/6a5884b83dcfde7f754810535e1130d923a26964))
- **release**: Add cocogitto + git-cliff release pipeline with log.sh distribution ([`90b89bc`](https://github.com/DevSecNinja/dotfiles/commit/90b89bc8b5f62bcb8d88cbd67bb1cce784ee4d9c))
- **scripts**: Handle apt held-back packages and quiet brew install loop ([`8871e94`](https://github.com/DevSecNinja/dotfiles/commit/8871e9499180349f35fe5468be2eef984d66312b))
- **scripts**: Adopt log.sh across chezmoi scripts (#237) ([`5dc1f84`](https://github.com/DevSecNinja/dotfiles/commit/5dc1f849966b648d24307754ce6cadb767cf394a))
- **vscode**: Add mcp configuration for GitHub Copilot and Microsoft Learn ([`f28174e`](https://github.com/DevSecNinja/dotfiles/commit/f28174e16ba960b95ddf0295889b97d98fdc6191))
- **log**: Add tab completion for log dispatcher ([`b6bf5a7`](https://github.com/DevSecNinja/dotfiles/commit/b6bf5a7e84362ab9a2160b268776c998e1bd8508))
- **log**: Rework shell logging library with kinds, banners, and JSON output ([`0881d64`](https://github.com/DevSecNinja/dotfiles/commit/0881d6455a53d44d786be265d58fcf9506ee2126))
- Migrate bats CI to truenas-apps style ([`22d0e68`](https://github.com/DevSecNinja/dotfiles/commit/22d0e68e4226b81b481c494ef6205b85ea4694c2))
- Implement improvements from felipecrs dotfiles investigation ([`0a19721`](https://github.com/DevSecNinja/dotfiles/commit/0a19721afe59f479e8d70909c3f28681e9e3714d))
- **github**: Disable telemetry in CLI ([`e7aeb66`](https://github.com/DevSecNinja/dotfiles/commit/e7aeb66370a5f20d09080187224f2cf2e28f90f8))
- Add loading of TrueNAS apps aliases in shell configurations ([`712fb90`](https://github.com/DevSecNinja/dotfiles/commit/712fb9023ea0451db88f83c6d48f2f0600ed1f21))
- Add comments for ForwardAgent in SSH config for clarity ([`6ce58f0`](https://github.com/DevSecNinja/dotfiles/commit/6ce58f00672d1ec9443b2102db5a3bf50b7e639a))
- Add forward agent for dev server ([`1b9d5a6`](https://github.com/DevSecNinja/dotfiles/commit/1b9d5a6a9f8eccf7590198bb650b5bbc846b1cb0))
- Add condition to only deploy these hosts to my non-work machines ([`7c4371d`](https://github.com/DevSecNinja/dotfiles/commit/7c4371d832df55135391b2ed7dd8912b8c32a50c))
- Add auto-execution for scripts when run directly ([`3961450`](https://github.com/DevSecNinja/dotfiles/commit/3961450a96d3b8f17dc62aa126c385a2a3f359d5))
- Add timing and output reporting to Bats tests ([`d97adc1`](https://github.com/DevSecNinja/dotfiles/commit/d97adc1ca6c492a170856557ea09c6e2f0d8bc7b))
- Add concurrency and timeout settings to all workflows ([`203e25c`](https://github.com/DevSecNinja/dotfiles/commit/203e25c2bbbe0e9f2521d7803cebc8a5e82a84bd))

### Miscellaneous
- **version**: V0.1.0 ([`408dbfa`](https://github.com/DevSecNinja/dotfiles/commit/408dbfa7ef5dae3f63882bdbbbd105265be888c1))
- Sign PowerShell scripts [skip ci] ([`ef53f12`](https://github.com/DevSecNinja/dotfiles/commit/ef53f12e285528c6f5f1a4f1e1331dec10230944))
- Sign PowerShell scripts [skip ci] ([`d4bf380`](https://github.com/DevSecNinja/dotfiles/commit/d4bf3801096a34d13d5dbe74432e0873792e5253))
- Sign PowerShell scripts [skip ci] ([`6cab2a0`](https://github.com/DevSecNinja/dotfiles/commit/6cab2a03b300ad29b62f56149194f03f99b4c32f))
- Sign PowerShell scripts [skip ci] ([`9a3a8f0`](https://github.com/DevSecNinja/dotfiles/commit/9a3a8f0a4f03b1e7d0b4d6a8489193a0d365b6c3))
- Sign PowerShell scripts [skip ci] ([`a384905`](https://github.com/DevSecNinja/dotfiles/commit/a384905df12def79d4027052c41f0e23121a483c))
- Sign PowerShell scripts [skip ci] ([`87fe27a`](https://github.com/DevSecNinja/dotfiles/commit/87fe27abd43ed771b6aff04816e10546d8802a81))
- Remove old renovate.json (replaced by renovate.json5) ([`3ca3528`](https://github.com/DevSecNinja/dotfiles/commit/3ca3528d0b5535981965a6c1b8f4fadd17adaa01))
- Standardize to central Renovate config ([`c0f5e55`](https://github.com/DevSecNinja/dotfiles/commit/c0f5e557358065b7613a95d880d97b6eb4038100))
- Add CODEOWNERS file ([`05a38cb`](https://github.com/DevSecNinja/dotfiles/commit/05a38cbf4efe0697471b5454f2ca2cec462604db))
- Sign PowerShell scripts [skip ci] ([`2599a79`](https://github.com/DevSecNinja/dotfiles/commit/2599a793f97d5c9ed0b76912e821de1eabb5ebe2))
- Sign PowerShell scripts [skip ci] ([`a3960ed`](https://github.com/DevSecNinja/dotfiles/commit/a3960edd6639ed4487de77aeebaed8cd0d7a2dd9))
- Sign PowerShell scripts [skip ci] ([`db0d885`](https://github.com/DevSecNinja/dotfiles/commit/db0d8852ba19d19fd47fb9ada5d17483ff1e31b0))
- Sign PowerShell scripts [skip ci] ([`145aab1`](https://github.com/DevSecNinja/dotfiles/commit/145aab118678227e3f85079e35670b41d6c445d4))
- Sign PowerShell scripts [skip ci] ([`963f1cc`](https://github.com/DevSecNinja/dotfiles/commit/963f1cc00bf961ab764354d9c84c0e416c61e94f))
- Sign PowerShell scripts [skip ci] ([`c71cd79`](https://github.com/DevSecNinja/dotfiles/commit/c71cd7902c03e8796ebaa521ece6e4dea334fff1))
- Sign PowerShell scripts [skip ci] ([`cad970b`](https://github.com/DevSecNinja/dotfiles/commit/cad970b0b552b1fcb1624e8ffb24f9b51dd0a117))
- Sign PowerShell scripts [skip ci] ([`d4e08ed`](https://github.com/DevSecNinja/dotfiles/commit/d4e08eda78a7b803bc494d21d41d208880e88f43))
- Sign PowerShell scripts [skip ci] ([`29bc6c7`](https://github.com/DevSecNinja/dotfiles/commit/29bc6c75eb7860091bed82afce2f78b880cb84fc))
- Sign PowerShell scripts [skip ci] ([`6a28cdf`](https://github.com/DevSecNinja/dotfiles/commit/6a28cdffe560da69036470ef8772682d6cda8e9a))
- Sign PowerShell scripts [skip ci] ([`961f913`](https://github.com/DevSecNinja/dotfiles/commit/961f91392199dd17c6fc6af4fc0588a442b033fd))
- Sign PowerShell scripts [skip ci] ([`a95dbb9`](https://github.com/DevSecNinja/dotfiles/commit/a95dbb991c0d270c90be9cdc4ae88e03c61db273))
- Sign PowerShell scripts [skip ci] ([`7894fb5`](https://github.com/DevSecNinja/dotfiles/commit/7894fb5225ca64dcc1b08ad02e016b58dd2b6c6e))
- Sign PowerShell scripts [skip ci] ([`336f67a`](https://github.com/DevSecNinja/dotfiles/commit/336f67ae640a05585226109f381e7bbb0ab396bb))
- Sign PowerShell scripts [skip ci] ([`6af3b31`](https://github.com/DevSecNinja/dotfiles/commit/6af3b3100f79d6b3efc6a6bc60d9b94f0872cc30))
- Sign PowerShell scripts [skip ci] ([`23820fd`](https://github.com/DevSecNinja/dotfiles/commit/23820fd65f6427a94e3729094f31adcddeed57c7))
- Sign PowerShell scripts [skip ci] ([`8ffe072`](https://github.com/DevSecNinja/dotfiles/commit/8ffe0726d5b68e791c0a54721d845b0f96b1ba24))
- Sync develop with main [skip ci] ([`fb2054d`](https://github.com/DevSecNinja/dotfiles/commit/fb2054d7eb9e4a13a9e8709cb9da029c678e3ffb))
- Sign PowerShell scripts [skip ci] ([`a2b5911`](https://github.com/DevSecNinja/dotfiles/commit/a2b5911992e1714dba6bf0dc7d80486b4651ac8d))
- Sign PowerShell scripts [skip ci] ([`8fd526b`](https://github.com/DevSecNinja/dotfiles/commit/8fd526bbd27f0d32fae49f5fb4076e1fbefa0b14))
- Sign PowerShell scripts [skip ci] ([`295c328`](https://github.com/DevSecNinja/dotfiles/commit/295c3282e43616bdf5228203e998fc7c84187dd6))
- Sign PowerShell scripts [skip ci] ([`ae2317f`](https://github.com/DevSecNinja/dotfiles/commit/ae2317f9b8f9b547a17f727b2aef23f093112408))
- Sync develop with main [skip ci] ([`dcb1681`](https://github.com/DevSecNinja/dotfiles/commit/dcb1681a325117a8b3a343a7bd91bad96f042a47))
- **config**: Migrate config renovate.json ([`e3edc1e`](https://github.com/DevSecNinja/dotfiles/commit/e3edc1ed5981221c63585efdeaf5f9c23e629b0c))

### Other
- Source functions.ps1 in onchange script (chezmoi scripts run outside profile context) ([`6fe67cb`](https://github.com/DevSecNinja/dotfiles/commit/6fe67cbcaf17a785e32203c1f697dce4d13a577b))
- Change go-task to task in mise configuration ([`b55bd4d`](https://github.com/DevSecNinja/dotfiles/commit/b55bd4ddebfb2951bda1c937eb322df1a963c789))
- Allow bash to be opened from fish shell ([`dfc5a8c`](https://github.com/DevSecNinja/dotfiles/commit/dfc5a8c7f2d40f8f2586fb112f55302c7e4c2214))
- Prevent install scripts from being copied to home directory ([`c384c75`](https://github.com/DevSecNinja/dotfiles/commit/c384c7574649d8a17ea9f32ff0002091b056cc0d))
- Remove python3.11-venv package to fix CI failure ([`02c786a`](https://github.com/DevSecNinja/dotfiles/commit/02c786ad7e1f4c7efc99f559434a284772bcd1b9))
- Don't do symlink but use loader ([`5de7b84`](https://github.com/DevSecNinja/dotfiles/commit/5de7b848630cbc7736421ed394913d72caa565fc))
- Don't use tmpl prefix ([`77fdbf4`](https://github.com/DevSecNinja/dotfiles/commit/77fdbf411977b1890ba37a02069a66423f9bf97a))

### Testing
- Assert deterministic password tr shim ([`4fdd963`](https://github.com/DevSecNinja/dotfiles/commit/4fdd963f6efcbca56eed50cc2070386bde85403b))

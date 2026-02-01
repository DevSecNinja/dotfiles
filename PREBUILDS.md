# DevContainer Prebuilds: Understanding the Difference

This document explains the two different approaches to prebuilding devcontainer images used in this repository.

## Quick Summary

**Two prebuild approaches:**

1. **Custom GitHub Actions Workflow** (`.github/workflows/devcontainer-prebuild.yaml`)
   - Builds and pushes images to GitHub Container Registry (GHCR)
   - Used by CI/CD pipelines and can be pulled by anyone
   - Provides maximum flexibility and control

2. **GitHub Codespaces Prebuilds** (Repository Settings → Codespaces)
   - Native GitHub feature for faster Codespaces startup
   - Managed entirely by GitHub
   - Only benefits GitHub Codespaces users

**Key Insight:** These are **complementary**, not mutually exclusive. You can use both!

---

## Approach 1: Custom GitHub Actions Workflow

### What It Does

The workflow file `.github/workflows/devcontainer-prebuild.yaml` builds the devcontainer image and publishes it to GitHub Container Registry (GHCR).

### How It Works

```yaml
# Triggers
- Push to main/develop (when devcontainer files change)
- Pull requests to main (validation only, no push)
- Weekly schedule (Mondays 3 AM UTC)
- Manual workflow dispatch

# Outputs
- Image: ghcr.io/devsecninja/dotfiles-devcontainer:latest
- Image: ghcr.io/devsecninja/dotfiles-devcontainer:develop
```

### Benefits

✅ **Universal Access**: Any tool/environment can pull the prebuilt image from GHCR
✅ **CI/CD Integration**: Used in CI workflows for faster test execution
✅ **Full Control**: Custom caching strategies, build triggers, and tags
✅ **Weekly Refreshes**: Automatically picks up base image updates
✅ **Multi-Branch Support**: Separate images for `main` and `develop` branches

### Where It's Used

1. **CI Pipeline** (`ci.yaml`):
   ```yaml
   # Uses prebuilt image as cache source
   devcontainer up --workspace-folder . \
     --cache-from type=registry,ref=ghcr.io/.../dotfiles-devcontainer:latest
   ```

2. **Local Development**: Developers can manually reference the prebuilt image in their local setup

3. **Any Consumer**: Any environment with Docker can pull and use these images

### Configuration

Located in: `.github/workflows/devcontainer-prebuild.yaml`

**Key settings:**
- Timeout: 45 minutes
- Only pushes on main/develop (PRs validate only)
- Uses Docker Buildx for efficient builds
- Includes layer caching

---

## Approach 2: GitHub Codespaces Prebuilds

### What It Does

GitHub's native prebuild feature in repository settings that prepares Codespaces environments in advance.

### How It Works

When enabled in **Repository Settings → Codespaces → Prebuilds**:

1. GitHub automatically detects changes to `.devcontainer/` files
2. Builds and caches the environment in GitHub's infrastructure
3. When a user creates a Codespace, it starts from the prebuilt state
4. Result: **Significantly faster Codespace startup time**

### Benefits

✅ **Zero Configuration**: No workflow files needed
✅ **Automatic Rebuilds**: GitHub handles everything
✅ **Faster Startup**: Codespaces start in seconds instead of minutes
✅ **GitHub Managed**: No need to manage container registry or caching

### Limitations

⚠️ **Codespaces Only**: Only benefits GitHub Codespaces users
⚠️ **No CI/CD Use**: Cannot be used in CI pipelines or local dev
⚠️ **Less Control**: Limited customization compared to custom workflows

### How to Enable

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Codespaces**
3. Under **Prebuilds**, click **Set up prebuild**
4. Configure:
   - **Branch**: Select `main` (and optionally `develop`)
   - **Configuration**: Select `.devcontainer/devcontainer.json`
   - **Triggers**: Automatically rebuilds on push
   - **Region**: Choose regions where your team is located

### Current Status

This repository mentions Codespaces prebuilds in the README as **optional**:

> **Optional:** Enable Codespaces prebuilds in repository settings for even faster startup

It is **not currently configured** but can be enabled by repository administrators.

---

## Comparison Table

| Feature | Custom Workflow | GitHub Codespaces Prebuilds |
|---------|----------------|----------------------------|
| **Purpose** | General-purpose prebuilt images | Codespaces startup only |
| **Image Location** | GHCR (public/private registry) | GitHub's internal cache |
| **Accessibility** | Anyone with registry access | Codespaces users only |
| **CI/CD Integration** | ✅ Yes (used in ci.yaml) | ❌ No |
| **Local Development** | ✅ Can be pulled/used | ❌ No |
| **Configuration** | YAML workflow file | Repository settings UI |
| **Customization** | Full control (triggers, caching, tags) | Limited (basic settings) |
| **Cost Control** | Manual control via workflow logic | GitHub-managed |
| **Build Triggers** | Custom (push, schedule, dispatch) | Automatic on devcontainer changes |
| **Multi-Branch** | ✅ Yes (main, develop) | ✅ Yes (configurable) |
| **Weekly Refresh** | ✅ Yes (cron schedule) | Depends on configuration |

---

## Which Approach Should You Use?

### Use Custom Workflow If:
- ✅ You need prebuilt images for CI/CD pipelines
- ✅ You want to share images across different environments
- ✅ You need fine-grained control over build timing and caching
- ✅ You want to support local development with prebuilt images
- ✅ You need multi-branch support with different tags

### Use Codespaces Prebuilds If:
- ✅ Your team primarily uses GitHub Codespaces
- ✅ You want zero-maintenance prebuild setup
- ✅ You want the fastest possible Codespace startup time
- ✅ You prefer GitHub-managed solutions

### Use Both If:
- ✅ You want the best of both worlds
- ✅ You have both CI/CD needs AND Codespaces users
- ✅ You want maximum performance across all scenarios

**This repository currently uses only the custom workflow.** Codespaces prebuilds can be enabled as an optional enhancement for Codespaces users.

---

## Current Implementation in This Repository

### What's Configured

1. **Custom Workflow**: ✅ Active
   - File: `.github/workflows/devcontainer-prebuild.yaml`
   - Images published to: `ghcr.io/devsecninja/dotfiles-devcontainer`
   - Used by CI pipeline in `ci.yaml`

2. **Codespaces Prebuilds**: ❌ Not configured (optional)
   - Can be enabled in repository settings
   - Would provide additional benefit for Codespaces users

### How CI Uses Prebuilt Images

In `.github/workflows/ci.yaml`, the `test-devcontainer` job uses the prebuilt image:

```yaml
- name: Build and start devcontainer
  run: |
    devcontainer up --workspace-folder . \
      --cache-from type=registry,ref=ghcr.io/${{ steps.lowercase.outputs.owner }}/dotfiles-devcontainer:latest \
      --cache-from type=local,src=/tmp/.buildx-cache \
      --cache-to type=local,dest=/tmp/.buildx-cache-new,mode=max
```

This significantly speeds up CI runs by:
1. Using the prebuilt image from GHCR as a cache source
2. Only rebuilding changed layers
3. Combining with local Docker layer cache

---

## Frequently Asked Questions

### Q: Do I need both approaches?

**A:** No. The custom workflow is sufficient for most use cases. Add Codespaces prebuilds only if your team frequently uses GitHub Codespaces and wants faster startup.

### Q: Will Codespaces work without enabling prebuilds?

**A:** Yes! Codespaces will build the devcontainer on first launch. It just takes longer (minutes instead of seconds).

### Q: Can I use the custom workflow images in Codespaces?

**A:** Not directly. Codespaces builds from the devcontainer configuration. However, the custom workflow's prebuilt images don't speed up Codespaces (that's what Codespaces prebuilds are for).

### Q: Do these approaches conflict?

**A:** No, they're complementary. They serve different purposes and can coexist.

### Q: How much faster is startup with prebuilds?

**A:** With Codespaces prebuilds, startup time typically reduces from 5-10 minutes to 30-60 seconds.

### Q: What about costs?

**A:**
- **Custom workflow**: Uses GitHub Actions minutes and GHCR storage (both free for public repos)
- **Codespaces prebuilds**: Uses Codespaces compute time (billed separately, free tier available)

---

## Additional Resources

- [DevContainers Specification](https://containers.dev/)
- [GitHub Actions: devcontainers/ci](https://github.com/devcontainers/ci)
- [GitHub Codespaces Prebuilds Documentation](https://docs.github.com/en/codespaces/prebuilding-your-codespaces/about-github-codespaces-prebuilds)
- [Docker Buildx Caching](https://docs.docker.com/build/cache/)

---

## Summary

**Current setup:**
- ✅ Custom workflow provides prebuilt images for CI/CD and general use
- ❌ Codespaces prebuilds not yet enabled (optional enhancement)

**Recommendation:**
- Keep the custom workflow (required for CI/CD)
- Optionally enable Codespaces prebuilds if your team uses Codespaces frequently

**They're not alternatives—they're complements that can work together!**

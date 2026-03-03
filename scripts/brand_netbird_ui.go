package main

import (
	"errors"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

const maxTextFileSize = 2 * 1024 * 1024

var (
	textExts = map[string]struct{}{
		".svg":     {},
		".xml":     {},
		".css":     {},
		".scss":    {},
		".less":    {},
		".js":      {},
		".jsx":     {},
		".ts":      {},
		".tsx":     {},
		".html":    {},
		".go":      {},
		".plist":   {},
		".json":    {},
		".desktop": {},
		".rc":      {},
	}

	hexColorPattern = regexp.MustCompile(`(?i)#(?:f69220|f7931e|ff8a00|f58220|fa962a)`)
	rgbColorPattern = regexp.MustCompile(`(?i)rgb\(\s*(?:246|247|255|245|250)\s*,\s*(?:146|147|138|130|150)\s*,\s*(?:32|30|0|42)\s*\)`)

	goTitlePattern       = regexp.MustCompile(`SetTitle\(\s*"NetBird"\s*\)`)
	goTooltipPattern     = regexp.MustCompile(`SetTooltip\(\s*"NetBird"\s*\)`)
	desktopNamePattern   = regexp.MustCompile(`(?m)^(\s*Name\s*=\s*)NetBird\s*$`)
	desktopCommentPatern = regexp.MustCompile(`(?m)^(\s*Comment\s*=\s*)NetBird\s*$`)
	plistNamePattern     = regexp.MustCompile(`(<string>)NetBird(</string>)`)
	jsonNamePattern      = regexp.MustCompile(`(?i)("(?:ProductName|FileDescription|InternalName|Title|CFBundleName|CFBundleDisplayName)"\s*:\s*)"NetBird"`)
)

type brandingConfig struct {
	netbirdDir   string
	brandName    string
	versionLabel string
	targetHex    string
	targetHash   string
	targetR      int
	targetG      int
	targetB      int
}

func main() {
	cfg, err := parseFlags()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[error] %v\n", err)
		os.Exit(1)
	}

	checked, changed, err := rewriteTextFiles(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[error] branding text rewrite failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[branding] checked text files: %d\n", checked)
	fmt.Printf("[branding] changed text files: %d\n", len(changed))
	limit := 30
	if len(changed) < limit {
		limit = len(changed)
	}
	for i := 0; i < limit; i++ {
		fmt.Printf("  - %s\n", changed[i])
	}
	if len(changed) > limit {
		fmt.Printf("  ... and %d more\n", len(changed)-limit)
	}

	checkedPNG, changedPNG, err := recolorPNGIcons(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[error] png recolor failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[branding] checked png icons: %d\n", checkedPNG)
	fmt.Printf("[branding] changed png icons: %d\n", changedPNG)
}

func parseFlags() (*brandingConfig, error) {
	var cfg brandingConfig
	flag.StringVar(&cfg.netbirdDir, "netbird-dir", "", "path to netbird source tree")
	flag.StringVar(&cfg.brandName, "brand-name", "", "brand display name")
	flag.StringVar(&cfg.versionLabel, "version-label", "", "tray tooltip/version label")
	flag.StringVar(&cfg.targetHex, "brand-color-hex", "", "brand color in hex (RRGGBB or #RRGGBB)")
	flag.Parse()

	if cfg.netbirdDir == "" {
		return nil, errors.New("missing --netbird-dir")
	}
	if cfg.brandName == "" {
		return nil, errors.New("missing --brand-name")
	}
	if cfg.versionLabel == "" {
		return nil, errors.New("missing --version-label")
	}
	normalizedHex, err := normalizeHex(cfg.targetHex)
	if err != nil {
		return nil, err
	}
	r, g, b := hexToRGB(normalizedHex)
	cfg.targetHex = normalizedHex
	cfg.targetHash = "#" + normalizedHex
	cfg.targetR = r
	cfg.targetG = g
	cfg.targetB = b

	info, err := os.Stat(cfg.netbirdDir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", cfg.netbirdDir)
	}
	return &cfg, nil
}

func normalizeHex(raw string) (string, error) {
	hex := strings.ToUpper(strings.TrimSpace(strings.TrimPrefix(raw, "#")))
	if len(hex) != 6 {
		return "", fmt.Errorf("invalid --brand-color-hex: %q", raw)
	}
	for _, ch := range hex {
		if (ch < '0' || ch > '9') && (ch < 'A' || ch > 'F') {
			return "", fmt.Errorf("invalid --brand-color-hex: %q", raw)
		}
	}
	return hex, nil
}

func hexToRGB(hex string) (int, int, int) {
	r64, _ := strconv.ParseInt(hex[0:2], 16, 32)
	g64, _ := strconv.ParseInt(hex[2:4], 16, 32)
	b64, _ := strconv.ParseInt(hex[4:6], 16, 32)
	return int(r64), int(g64), int(b64)
}

func rewriteTextFiles(cfg *brandingConfig) (int, []string, error) {
	checked := 0
	changedFiles := make([]string, 0)

	err := filepath.Walk(cfg.netbirdDir, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if info.IsDir() {
			return nil
		}
		if !isAllowedTextExt(path) {
			return nil
		}
		if !shouldScanText(path) {
			return nil
		}
		if info.Size() > maxTextFileSize {
			return nil
		}

		checked++
		contentBytes, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		content := string(contentBytes)
		if !isUTF8(contentBytes) {
			return nil
		}

		newContent := rewriteTextContent(cfg, path, content)
		if newContent == content {
			return nil
		}

		if err := os.WriteFile(path, []byte(newContent), info.Mode().Perm()); err != nil {
			return err
		}
		rel, relErr := filepath.Rel(cfg.netbirdDir, path)
		if relErr != nil {
			changedFiles = append(changedFiles, path)
		} else {
			changedFiles = append(changedFiles, filepath.ToSlash(rel))
		}
		return nil
	})

	if err != nil {
		return checked, changedFiles, err
	}
	return checked, changedFiles, nil
}

func rewriteTextContent(cfg *brandingConfig, path, content string) string {
	out := content
	out = hexColorPattern.ReplaceAllString(out, cfg.targetHash)
	out = rgbColorPattern.ReplaceAllString(out, fmt.Sprintf("rgb(%d, %d, %d)", cfg.targetR, cfg.targetG, cfg.targetB))

	if !looksUIRelated(path) {
		return out
	}

	quotedBrand := strconv.Quote(cfg.brandName)
	quotedLabel := strconv.Quote(cfg.versionLabel)
	escapedBrand := escapeReplacement(cfg.brandName)
	escapedLabel := escapeReplacement(cfg.versionLabel)

	out = goTitlePattern.ReplaceAllString(out, "SetTitle("+quotedBrand+")")
	out = goTooltipPattern.ReplaceAllString(out, "SetTooltip("+quotedLabel+")")
	out = desktopNamePattern.ReplaceAllString(out, "${1}"+escapedBrand)
	out = desktopCommentPatern.ReplaceAllString(out, "${1}"+escapedLabel)
	out = plistNamePattern.ReplaceAllString(out, "${1}"+escapedBrand+"${2}")
	out = jsonNamePattern.ReplaceAllString(out, "${1}\""+escapedBrand+"\"")
	return out
}

func escapeReplacement(s string) string {
	return strings.ReplaceAll(s, "$", "$$")
}

func isUTF8(data []byte) bool {
	return utf8.Valid(data)
}

func isAllowedTextExt(path string) bool {
	ext := strings.ToLower(filepath.Ext(path))
	_, ok := textExts[ext]
	return ok
}

func shouldScanText(path string) bool {
	low := strings.ToLower(filepath.ToSlash(path))
	if strings.Contains(low, "/client/") {
		return true
	}
	if strings.Contains(low, "/release_files/") {
		return true
	}
	return strings.HasSuffix(low, "versioninfo.json")
}

func looksUIRelated(path string) bool {
	low := strings.ToLower(filepath.ToSlash(path))
	tokens := []string{
		"client/ui",
		"netbird-ui",
		"tray",
		"icon",
		"desktop",
		"info.plist",
		"versioninfo",
	}
	for _, token := range tokens {
		if strings.Contains(low, token) {
			return true
		}
	}
	return false
}

func recolorPNGIcons(cfg *brandingConfig) (int, int, error) {
	targetR, targetG, targetB := mustHexColor(cfg.targetHex)
	targetHue, _, _ := rgbToHSV(targetR, targetG, targetB)

	checked := 0
	changed := 0

	err := filepath.Walk(cfg.netbirdDir, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if info.IsDir() {
			return nil
		}
		if strings.ToLower(filepath.Ext(path)) != ".png" {
			return nil
		}
		if !pathLooksLikeIcon(path) {
			return nil
		}
		checked++
		ok, err := recolorPNG(path, targetHue)
		if err != nil {
			return nil
		}
		if ok {
			changed++
		}
		return nil
	})
	if err != nil {
		return checked, changed, err
	}

	return checked, changed, nil
}

func mustHexColor(hex string) (float64, float64, float64) {
	hex = strings.TrimPrefix(strings.TrimSpace(hex), "#")
	if len(hex) != 6 {
		panic("invalid hex color")
	}
	r, err := strconv.ParseInt(hex[0:2], 16, 32)
	if err != nil {
		panic(err)
	}
	g, err := strconv.ParseInt(hex[2:4], 16, 32)
	if err != nil {
		panic(err)
	}
	b, err := strconv.ParseInt(hex[4:6], 16, 32)
	if err != nil {
		panic(err)
	}
	return float64(r) / 255.0, float64(g) / 255.0, float64(b) / 255.0
}

func rgbToHSV(r, g, b float64) (float64, float64, float64) {
	maxv := math.Max(r, math.Max(g, b))
	minv := math.Min(r, math.Min(g, b))
	delta := maxv - minv

	var h float64
	if delta == 0 {
		h = 0
	} else if maxv == r {
		h = math.Mod((g-b)/delta, 6.0)
	} else if maxv == g {
		h = (b-r)/delta + 2.0
	} else {
		h = (r-g)/delta + 4.0
	}
	h *= 60.0
	if h < 0 {
		h += 360.0
	}

	var s float64
	if maxv == 0 {
		s = 0
	} else {
		s = delta / maxv
	}
	return h, s, maxv
}

func hsvToRGB(h, s, v float64) (float64, float64, float64) {
	c := v * s
	x := c * (1 - math.Abs(math.Mod(h/60.0, 2)-1))
	m := v - c

	var rp, gp, bp float64
	switch {
	case h < 60:
		rp, gp, bp = c, x, 0
	case h < 120:
		rp, gp, bp = x, c, 0
	case h < 180:
		rp, gp, bp = 0, c, x
	case h < 240:
		rp, gp, bp = 0, x, c
	case h < 300:
		rp, gp, bp = x, 0, c
	default:
		rp, gp, bp = c, 0, x
	}
	return rp + m, gp + m, bp + m
}

func clamp255(v float64) uint8 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 255
	}
	return uint8(math.Round(v * 255))
}

func isOrange(h, s, v float64) bool {
	return h >= 5 && h <= 70 && s >= 0.22 && v >= 0.18
}

func recolorPNG(path string, targetHue float64) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer f.Close()

	img, err := png.Decode(f)
	if err != nil {
		return false, err
	}

	bounds := img.Bounds()
	dst := image.NewRGBA(bounds)
	changed := false

	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r16, g16, b16, a16 := img.At(x, y).RGBA()
			if a16 == 0 {
				dst.SetRGBA(x, y, color.RGBA{0, 0, 0, 0})
				continue
			}
			r := float64(r16) / 65535.0
			g := float64(g16) / 65535.0
			b := float64(b16) / 65535.0
			h, s, v := rgbToHSV(r, g, b)
			if isOrange(h, s, v) {
				nr, ng, nb := hsvToRGB(targetHue, s, v)
				dst.SetRGBA(x, y, color.RGBA{
					R: clamp255(nr),
					G: clamp255(ng),
					B: clamp255(nb),
					A: uint8(a16 >> 8),
				})
				changed = true
			} else {
				dst.SetRGBA(x, y, color.RGBA{
					R: uint8(r16 >> 8),
					G: uint8(g16 >> 8),
					B: uint8(b16 >> 8),
					A: uint8(a16 >> 8),
				})
			}
		}
	}

	if !changed {
		return false, nil
	}

	tmpPath := path + ".tmp"
	out, err := os.Create(tmpPath)
	if err != nil {
		return false, err
	}
	if err := png.Encode(out, dst); err != nil {
		_ = out.Close()
		return false, err
	}
	if err := out.Close(); err != nil {
		return false, err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return false, err
	}
	return true, nil
}

func pathLooksLikeIcon(path string) bool {
	low := strings.ToLower(path)
	sep := string(filepath.Separator)
	if !strings.Contains(low, sep+"client"+sep) {
		return false
	}
	return strings.Contains(low, "icon") ||
		strings.Contains(low, "tray") ||
		strings.Contains(low, "logo") ||
		strings.Contains(low, "bird") ||
		strings.Contains(low, sep+"ui"+sep) ||
		strings.Contains(low, sep+"assets"+sep)
}

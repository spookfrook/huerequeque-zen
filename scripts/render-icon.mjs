#!/usr/bin/env node
// Genera la marca de Huerequeque Zen (familia Llama Encargada):
// Resources/Huerequeque.svg, Resources/Huerequeque.png (cuadrado full-bleed para el panel),
// Resources/HuerequequeIcon.png (1024x1024 con ficha macOS y sombra), y .build/icon-sheet.png.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const RES = path.join(ROOT, "Resources");
const BUILD = path.join(ROOT, ".build");
fs.mkdirSync(RES, { recursive: true });
fs.mkdirSync(BUILD, { recursive: true });

// Tokens exactos de ~/code/personal/hoja-de-estilo/tokens/llama.tokens.json
const TILE_TOP = "#6e6bf0";
const TILE_BOTTOM = "#4441bd";
const CREAM = "#fff8ea";
const AMBER = "#ffbd45";
const PAPER = "#5855d6";

// Huerequeque (Burhinus superciliaris) estilo papel recortado, hermano de Liron Sereno y Mussol Feiner:
// cuerpo regordete y sereno en equilibrio zen sobre una pata, ceja distintiva, ojo cerrado en paz,
// y su ala/pecho protegiendo un candado zen ambar integrado en la composicion.
function drawHuerequeque({ small = false } = {}) {
  if (small) {
    return `
      <!-- Cabeza y cuerpo gruesos para legibilidad a 16 px -->
      <path fill="${CREAM}" d="
        M 18 17
        C 18 9, 34 8.5, 36.5 16
        L 45 18
        L 36.5 22
        C 35.5 25, 35 28, 36 33
        C 37 42, 31 48, 21 48
        L 10 51
        L 13.5 41.5
        C 10.5 36, 12 26.5, 18.5 23.5
        Z
      "/>
      <path fill="none" stroke="${CREAM}" stroke-width="4" stroke-linecap="round" d="M 22 47 V 56 M 16.5 56 H 28"/>
      <path fill="none" stroke="${PAPER}" stroke-width="2.8" stroke-linecap="round" d="M 24.5 17.2 Q 28.5 20.5 32.5 17.2"/>
      <!-- Candado ambar compacto -->
      <path fill="none" stroke="${AMBER}" stroke-width="3.6" stroke-linecap="round" d="M 39.5 36 V 31.5 A 5.2 5.2 0 0 1 50 31.5 V 36"/>
      <rect x="35.5" y="35.2" width="18.5" height="16.2" rx="4.2" fill="${AMBER}"/>
      <circle cx="44.75" cy="43" r="2.4" fill="${PAPER}"/>
    `;
  }

  return `
    <!-- Pata zen apoyada (una sola pata larga de huerequeque) -->
    <path fill="none" stroke="${CREAM}" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round" d="
      M 21.8 43.2 L 21.8 54.2
      M 16.2 54.2 L 28.0 54.2
    "/>
    <!-- Pata recogida en equilibrio -->
    <path fill="none" stroke="${CREAM}" stroke-width="3.0" stroke-linecap="round" stroke-linejoin="round" d="
      M 26.5 44.0 L 30.2 48.0 L 25.5 50.2
    "/>

    <!-- Silueta principal del huerequeque: cabeza generosa, pico corto firme, pecho amplio, cola elegante -->
    <path fill="${CREAM}" d="
      M 17.8 18.2
      C 17.8 10.6, 25.2 7.2, 32.8 8.8
      C 36.8 9.7, 39.6 12.6, 40.4 16.0
      L 49.4 18.2
      C 50.4 18.5, 50.4 19.8, 49.3 20.1
      L 40.2 22.8
      C 38.6 25.6, 36.2 27.2, 35.4 29.6
      C 34.4 32.6, 35.2 38.6, 32.0 42.8
      C 29.0 46.6, 24.4 47.4, 19.6 46.8
      L 10.0 51.6
      C 8.7 52.2, 7.6 51.0, 8.5 49.8
      L 13.4 42.4
      C 9.6 38.0, 9.8 30.2, 15.2 25.6
      C 17.4 23.7, 17.8 21.2, 17.8 18.2 Z
    "/>

    <!-- Ceja distintiva del huerequeque (Burhinus superciliaris) -->
    <path fill="none" stroke="${PAPER}" stroke-width="2.1" stroke-linecap="round" d="
      M 24.4 12.6 Q 29.4 10.6 34.6 12.8
    "/>

    <!-- Ojo zen cerrado con expresion serena -->
    <path fill="none" stroke="${PAPER}" stroke-width="2.6" stroke-linecap="round" d="
      M 25.4 17.8 Q 29.8 21.6 34.4 17.6
    "/>

    <!-- Pequeña sonrisa serena bajo el pico -->
    <path fill="none" stroke="${PAPER}" stroke-width="1.8" stroke-linecap="round" d="
      M 37.8 21.6 Q 40.0 22.8 42.0 21.4
    "/>

    <!-- Recorte negativo indigo separando el candado y el ala del pecho -->
    <path fill="none" stroke="${PAPER}" stroke-width="2.6" stroke-linecap="round" d="
      M 15.6 39.2 C 20.2 40.6, 26.8 38.4, 29.6 32.8
    "/>

    <!-- Contorno separador indigo detras del candado para efecto papel recortado (usa el gradiente del fondo) -->
    <path fill="none" stroke="url(#__GRAD__)" stroke-width="6.4" stroke-linecap="round" d="
      M 40.2 37.8 V 33.0 A 5.4 5.4 0 0 1 51.0 33.0 V 37.8
    "/>
    <rect x="34.2" y="35.6" width="22.8" height="20.4" rx="6.2" fill="url(#__GRAD__)"/>

    <!-- Candado zen ambar (el unico acento funcional) -->
    <path fill="none" stroke="${AMBER}" stroke-width="3.4" stroke-linecap="round" d="
      M 40.2 38.0 V 33.0 A 5.4 5.4 0 0 1 51.0 33.0 V 38.0
    "/>
    <rect x="36.2" y="37.4" width="18.8" height="16.8" rx="4.6" fill="${AMBER}"/>
    <circle cx="45.6" cy="44.2" r="2.25" fill="${PAPER}"/>
    <path fill="none" stroke="${PAPER}" stroke-width="2.0" stroke-linecap="round" d="M 45.6 45.8 V 49.4"/>

    <!-- Punta del ala crema abrazando suavemente el candado (gesto del oficio!) -->
    <path fill="${CREAM}" d="
      M 27.4 30.8
      C 32.4 29.8, 37.4 31.8, 39.2 35.8
      C 40.1 37.8, 38.4 39.6, 36.2 39.2
      C 33.2 38.6, 30.0 37.0, 27.6 34.4 Z
    "/>
  `;
}

function makeTileSVG({ rx = 0, small = false, id = "g0" } = {}) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <defs>
    <linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="${TILE_TOP}"/>
      <stop offset="100%" stop-color="${TILE_BOTTOM}"/>
    </linearGradient>
    <clipPath id="c${id}">
      <rect width="64" height="64" rx="${rx}"/>
    </clipPath>
  </defs>
  <rect width="64" height="64" rx="${rx}" fill="url(#${id})"/>
  <g clip-path="url(#c${id})">
    ${drawHuerequeque({ small }).replaceAll("__GRAD__", id)}
  </g>
</svg>`;
}

function makeDesktopIconSVG() {
  const inner = makeTileSVG({ rx: 14.4, small: false, id: "desk" }).replace(/<\/?svg[^>]*>/g, "");
  const scale = 824 / 64;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <filter id="sombra" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14"/>
    </filter>
  </defs>
  <rect x="100" y="112" width="824" height="824" rx="185" fill="#000" opacity=".28" filter="url(#sombra)"/>
  <g transform="translate(100 100) scale(${scale})">${inner}</g>
</svg>`;
}

function renderPNG(svg, width, height, outPath) {
  execFileSync("rsvg-convert", ["-w", String(width), "-h", String(height), "-o", outPath], { input: svg });
}

const fullBleedSVG = makeTileSVG({ rx: 0, small: false, id: "tile" });
fs.writeFileSync(path.join(RES, "Huerequeque.svg"), fullBleedSVG);
renderPNG(fullBleedSVG, 512, 512, path.join(RES, "Huerequeque.png"));

const deskSVG = makeDesktopIconSVG();
renderPNG(deskSVG, 1024, 1024, path.join(RES, "HuerequequeIcon.png"));

const smallSVG = makeTileSVG({ rx: 14.4, small: true, id: "small" });
renderPNG(smallSVG, 32, 32, path.join(RES, "HuerequequeSmall32.png"));

// Hoja de verificacion proporcional (560x280) con 200px, 64px, 32px y 16px en claro y oscuro
const sheetSVG = `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="280" viewBox="0 0 600 280">
  <rect width="300" height="280" fill="#f2f2f7"/>
  <rect x="300" width="300" height="280" fill="#000000"/>
  <g transform="translate(24 40) scale(${180 / 64})">${makeTileSVG({ rx: 14.4, id: "s1" }).replace(/<\/?svg[^>]*>/g, "")}</g>
  <g transform="translate(218 40) scale(${64 / 64})">${makeTileSVG({ rx: 14.4, id: "s2" }).replace(/<\/?svg[^>]*>/g, "")}</g>
  <g transform="translate(218 124) scale(${32 / 64})">${makeTileSVG({ rx: 14.4, id: "s3" }).replace(/<\/?svg[^>]*>/g, "")}</g>
  <g transform="translate(218 176) scale(${16 / 64})">${makeTileSVG({ rx: 14.4, small: true, id: "s4" }).replace(/<\/?svg[^>]*>/g, "")}</g>
  <g transform="translate(324 40) scale(${180 / 64})">${makeTileSVG({ rx: 14.4, id: "s5" }).replace(/<\/?svg[^>]*>/g, "")}</g>
  <g transform="translate(518 40) scale(${64 / 64})">${makeTileSVG({ rx: 14.4, id: "s6" }).replace(/<\/?svg[^>]*>/g, "")}</g>
  <g transform="translate(518 124) scale(${32 / 64})">${makeTileSVG({ rx: 14.4, id: "s7" }).replace(/<\/?svg[^>]*>/g, "")}</g>
  <g transform="translate(518 176) scale(${16 / 64})">${makeTileSVG({ rx: 14.4, small: true, id: "s8" }).replace(/<\/?svg[^>]*>/g, "")}</g>
</svg>`;
renderPNG(sheetSVG, 600, 280, path.join(BUILD, "icon-sheet.png"));

console.log("Rendered refined Huerequeque Zen icons.");

# 낮고 넓은 직조 광주리

참고 이미지에 맞춘 Roblox용 오픈탑 광주리 에셋입니다.

## 파일

- `LowWideWovenBasket.blend`: 각 직조 조각을 편집할 수 있는 Blender 원본
- `LowWideWovenBasket_Roblox.fbx`: Roblox Studio 3D Importer용 단일 메시
- `LowWideWovenBasket.glb`: 재질 확인 및 다른 3D 도구용
- `LowWideWovenBasket_preview.png`: 완성 형태 미리보기

## 기준 치수

- 상단 외곽: 2.55 × 2.20 studs
- 하단 외곽 목표: 2.05 × 1.55 studs
- 전체 높이: 0.90 studs
- 피벗 기준: 바구니 중앙, 바닥면 Z=0
- 위가 열린 시각 메시이며 손잡이는 없습니다.

## Roblox Studio에 넣기

1. Studio에서 **Home > Import 3D**를 누릅니다.
2. `LowWideWovenBasket_Roblox.fbx`를 선택합니다.
3. 한 개의 MeshPart로 가져오고 이름을 `BasketVisualMesh`로 정합니다.
4. 가져온 결과의 `Size`가 `2.55, 0.90, 2.20`인지 확인합니다. Roblox 좌표에서는 Y가 높이입니다.
5. `CanCollide`, `CanTouch`, `CanQuery`를 끄고 `Massless`를 켭니다.
6. 게임의 `Basket.Bottom` 중심에 맞춘 뒤 `WeldConstraint`로 `Bottom`에 연결합니다.

달걀 충돌에는 시각 메시의 정밀 충돌을 사용하지 마세요. 현재 프로젝트의
`EggCollisionShell` 5파트 구조를 그대로 유지해야 달걀이 안정적으로 담기고 캐릭터와 충돌하지 않습니다.

이 FBX는 재질 슬롯을 포함합니다. Studio에서 색이 다르게 보이면 Import 3D 창의 재질 가져오기를 켜거나,
MeshPart의 `TextureID`/`SurfaceAppearance` 대신 포함된 재질별 기본색을 기준으로 조정하세요.

## 다시 생성하기

Blender가 `/Applications/Blender.app`에 설치된 macOS 환경에서는 프로젝트 루트에서 다음 명령으로
원본, FBX, GLB, 미리보기를 모두 다시 만들 수 있습니다.

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_woven_basket.py
```

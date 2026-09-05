# Supplied model review and calibration plan

## What `best.pt` contains

The submitted checkpoint is structurally valid and approximately 6 MB. Its stored training metadata identifies:

| Item | Value |
|---|---|
| Architecture | Ultralytics YOLOv8n detection model |
| Classes | `{0: fire}` |
| Training image size | 640 |
| Epochs | 50 |
| Batch | 16 |
| SHA-256 | `4f64f75d8a10deb4c0079622018fa876a9d55a13eb1058114aa4315b5dd8620d` |
| Stored precision | 0.83047 |
| Stored recall | 0.83681 |
| Stored mAP50 | 0.86416 |
| Stored mAP50–95 | 0.52727 |

These are validation-set metrics saved in the checkpoint. They are not proof of performance on the three installed C230 views and are not a safety certification.

## Important limitations

- The model has only the `fire` class. It cannot detect smoke.
- It has no `display_screen`/`screen` class. The backend contains containment-based screen suppression for a future multi-class model, but it cannot operate with this one-class checkpoint.
- Night vision, reflections, sunsets, orange/red objects, phone/TV video, cooking, compression artifacts, small distant flames, partial occlusion, and camera motion require site testing.
- Model confidence is a classification score, not fire size, heat, growth rate, or danger severity. The app labels this explicitly.

## Recommended calibration sequence

1. Begin with the **Balanced** preset and no advanced confidence override.
2. Install all cameras in their final positions. Avoid direct windows, reflective surfaces, screens, and strong moving lights where possible.
3. Collect representative clips for every camera in daytime, nighttime/IR, lights switching, people moving, fans/curtains, reflective glare, cooking activity, and screen playback.
4. Use controlled footage or a professionally supervised test source. Never create an uncontrolled indoor flame for app testing.
5. Record false alarms in the app with a reason. Export those frames later as hard-negative training examples.
6. Measure separately for each condition: event recall, false alarms per camera-hour, time to confirmed alarm, time to critical alarm, and recovery time.
7. Change only one control at a time. Use **High** only if missed/late detections are the main failure; use **Reduced false alarms** if nuisance detections dominate.
8. Use the advanced confidence override only after the presets are measured on held-out site footage.

## Best next model improvement

Retrain with at least these labels:

- `fire`
- `display_screen`

Add hard negatives with no boxes: red/orange objects, sunlight, reflections, lamps, cooking glow, emergency lights, and fire shown on screens. Keep a site-specific test set completely separate from training/validation. Report precision/recall and event-level false alarms, not only mAP.

For Raspberry Pi performance, benchmark the `.pt` model first and then compare an exported NCNN model. Do not change runtime format until detection parity is verified on the same held-out videos.

## Licensing check

This package uses the Ultralytics runtime and a YOLOv8-derived checkpoint. Before distributing or commercializing the system, review the current Ultralytics AGPL-3.0/Enterprise terms and obtain project-specific legal advice if needed.

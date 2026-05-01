# Keep all classes to avoid R8 minification issues
-keep class * { *; }
-keepclassmembers class * { *; }

# Disable optimizations that might remove needed code
-dontoptimize


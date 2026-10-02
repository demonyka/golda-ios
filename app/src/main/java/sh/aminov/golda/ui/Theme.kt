package sh.aminov.golda.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle

/** The gold of the one action to take: the mic, Записать, Сохранить, Купить, Беру. */
@Immutable
class ActionColors(val container: Color, val content: Color)

private val LocalAction = staticCompositionLocalOf { ActionColors(Color.Unspecified, Color.Unspecified) }

/** The gold behind the one action on a screen or sheet. */
@Composable
@ReadOnlyComposable
fun actionColor(): Color = LocalAction.current.container

/** Ink on [actionColor]. */
@Composable
@ReadOnlyComposable
fun onActionColor(): Color = LocalAction.current.content

/**
 * Colors.kt puts the gold on primary. Every M3 component reaches for primary on its own (switches,
 * date-picker selection, text buttons, cursors, focus, progress, the snackbar's action), so the
 * scheme the app runs with hands primary the graphite of "what is picked" instead, and the gold is
 * only where a composable asks for it by name: [actionColor].
 */
private fun ColorScheme.goldOnlyByName(): ColorScheme = copy(
    primary = secondary,
    onPrimary = onSecondary,
    primaryContainer = secondaryContainer,
    onPrimaryContainer = onSecondaryContainer,
    // The snackbar's action sits on the inverse surface: the quiet line tone reads on it in both themes.
    inversePrimary = outline,
)

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun GoldaTheme(content: @Composable () -> Unit) {
    val base = if (isSystemInDarkTheme()) DarkColors else LightColors
    CompositionLocalProvider(LocalAction provides ActionColors(base.primary, base.onPrimary)) {
        MaterialExpressiveTheme(
            colorScheme = base.goldOnlyByName(),
            motionScheme = MotionScheme.expressive(),
            content = content,
        )
    }
}

/** Tabular figures, so columns of amounts line up. */
val Tnum = TextStyle(fontFeatureSettings = "tnum")

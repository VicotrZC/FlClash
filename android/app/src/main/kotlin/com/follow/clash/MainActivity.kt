package com.follow.clash

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.follow.clash.common.Components
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.BatteryPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 冷启动：必须在 super.onCreate 之前把 intent 换掉，Flutter 引擎起来时
        // app_links 才会把这条深链当作 initial link 读走。
        intent = tilePreferencesDeepLink(intent) ?: intent
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(BatteryPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        ServiceState.attachFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        // 热启动：app_links 的 NewIntentListener 是在 onNewIntent 里读 intent 的
        // （AppLinksHelper.getUrl），而 QS_TILE_PREFERENCES 本身没有 data URI，
        // 直接传下去它什么都不会发出。所以先把 intent 换成深链再交给 super。
        val converted = tilePreferencesDeepLink(intent) ?: intent
        setIntent(converted)
        super.onNewIntent(converted)
    }

    /**
     * 磁贴长按由系统走 QS_TILE_PREFERENCES 落到本 Activity。系统默认只是把 App
     * 打开到上次的页面，而用户长按磁贴通常是想换节点，所以转成深链交给 Dart 侧跳页。
     *
     * @return 深链 intent；不是磁贴长按时返回 null，调用方沿用原 intent。
     */
    private fun tilePreferencesDeepLink(intent: Intent?): Intent? {
        if (intent?.action != TILE_PREFERENCES_ACTION) {
            return null
        }
        return Intent(Intent.ACTION_VIEW, Uri.parse("flclash://$PROXIES_HOST")).apply {
            setComponent(Components.mainActivity)
        }
    }

    override fun onDestroy() {
        flutterEngine?.let(ServiceState::detachFlutterEngine)
        super.onDestroy()
    }

    private companion object {
        const val TILE_PREFERENCES_ACTION =
            "android.service.quicksettings.action.QS_TILE_PREFERENCES"
        const val PROXIES_HOST = "proxies"
    }
}

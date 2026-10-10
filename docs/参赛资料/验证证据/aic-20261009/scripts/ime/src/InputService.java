package cn.semesteros.qa.ime;
import android.inputmethodservice.InputMethodService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.util.Base64;
import android.view.View;
import android.widget.TextView;
import java.nio.charset.StandardCharsets;

public class InputService extends InputMethodService {
  private final BroadcastReceiver receiver = new BroadcastReceiver() {
    @Override public void onReceive(Context context, Intent intent) {
      if (getCurrentInputConnection() != null && getCurrentInputEditorInfo() != null
          && "cn.semesteros.semester_os.qa".equals(getCurrentInputEditorInfo().packageName)
          && intent.hasExtra("data")) {
        String text = new String(Base64.decode(intent.getStringExtra("data"), Base64.DEFAULT), StandardCharsets.UTF_8);
        getCurrentInputConnection().performContextMenuAction(android.R.id.selectAll);
        getCurrentInputConnection().commitText(text, 1);
      }
    }
  };
  @Override public void onCreate() {
    super.onCreate();
    registerReceiver(receiver, new IntentFilter("cn.semesteros.qa.ime.INPUT"), Context.RECEIVER_EXPORTED);
  }
  @Override public View onCreateInputView() {
    TextView view = new TextView(this);
    view.setText("AIC isolated QA input"); view.setPadding(8, 8, 8, 8);
    return view;
  }
  @Override public void onDestroy() { unregisterReceiver(receiver); super.onDestroy(); }
}

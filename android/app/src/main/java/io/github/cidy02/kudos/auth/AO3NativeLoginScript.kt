package io.github.cidy02.kudos.auth

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

internal object AO3NativeLoginScript {
    // JSON literals escape every control character without recording credentials anywhere.
    fun fill(username: String, password: String): String = """
        (function() {
          if (location.protocol !== 'https:' || location.hostname !== 'archiveofourown.org') {
            return JSON.stringify({ok:false, reason:'bad-host'});
          }
          var form = document.querySelector('form#new_user, form[action*="/users/login"]');
          if (!form) return JSON.stringify({ok:false, reason:'no-form'});
          var u = form.querySelector('input[name="user[login]"]');
          var p = form.querySelector('input[name="user[password]"]');
          if (!u || !p) return JSON.stringify({ok:false, reason:'no-fields'});
          u.value = ${JsonPrimitive(username)};
          p.value = ${JsonPrimitive(password)};
          var r = form.querySelector('#user_remember_me, input[type="checkbox"][name="user[remember_me]"]');
          if (r) r.checked = true;
          setTimeout(function() {
            if (form.requestSubmit) form.requestSubmit();
            else form.submit();
          }, 0);
          return JSON.stringify({ok:true});
        })();
    """.trimIndent()

    fun requiresFallback(inspection: AO3WebLoginInspection): Boolean =
        !inspection.loggedIn && inspection.errorMessage == null

    fun submitted(raw: String?): Boolean =
        (loginJavascriptObject(raw)?.get("ok") as? JsonPrimitive)?.booleanOrNull == true
}

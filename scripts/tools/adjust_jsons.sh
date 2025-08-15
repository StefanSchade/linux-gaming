for f in config/*/game.json; do
  tmp="$f.tmp"
  jq '(.engine) as $old
      | .engine =
          ( if ($old // "" | ascii_upcase) == "DOSBOX" then "DOSBOX"
            else if ((.installer_type // "" | ascii_upcase) == "MULTI_DISC_ZIP")
                 then "WINE-DISK-MEDIA"
                 else "WINE-INSTALLER"
                 end
            end )' "$f" > "$tmp" && mv "$tmp" "$f"
done


/* Smoke test of the Ghillie mobile C bridge against CAMO's real wallet library on a private regtest chain.
   usage: smoke create <dir>          -> creates wallets A and B, prints A's address
          smoke send <dir> <daemon>   -> syncs A, sends 5 CAMO to a NEW subaddress of B, mines nothing itself
          smoke check <dir> <daemon>  -> syncs B, prints its balance and history */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "camo_wallet_ffi.h"

static camo_wallet *open_or_die(const char *path) {
  camo_wallet *w = camo_wallet_open(path, "", 0);
  if (!w) { fprintf(stderr, "open %s: %s\n", path, camo_last_error()); exit(1); }
  return w;
}
static void sync_w(camo_wallet *w, const char *daemon) {
  if (!camo_wallet_connect(w, daemon, 1)) { fprintf(stderr, "connect: %s\n", camo_wallet_error(w)); exit(1); }
  if (!camo_wallet_refresh_now(w)) { fprintf(stderr, "refresh: %s\n", camo_wallet_error(w)); exit(1); }
  printf("height %llu/%llu balance %llu unlocked %llu\n", (unsigned long long)camo_wallet_height(w),
         (unsigned long long)camo_wallet_daemon_height(w), (unsigned long long)camo_wallet_balance(w),
         (unsigned long long)camo_wallet_unlocked_balance(w));
}

int main(int argc, char **argv) {
  if (argc < 3) return 2;
  char a[512], b[512];
  snprintf(a, sizeof a, "%s/A", argv[2]);
  snprintf(b, sizeof b, "%s/B", argv[2]);
  if (!strcmp(argv[1], "create")) {
    camo_wallet *wa = camo_wallet_create(a, "", "English", 0), *wb = camo_wallet_create(b, "", "English", 0);
    if (!wa || !wb) { fprintf(stderr, "create: %s\n", camo_last_error()); return 1; }
    printf("A %s\n", camo_wallet_address(wa, 0));
    printf("A seed words: %d\n", (int)(strlen(camo_wallet_seed(wa)) > 100));
    printf("valid %d invalid-net %d\n", camo_address_valid(camo_wallet_address(wa, 0), 0), camo_address_valid(camo_wallet_address(wa, 0), 2));
    camo_wallet_close(wa, 1); camo_wallet_close(wb, 1);
    return 0;
  }
  if (argc < 4) return 2;
  if (!strcmp(argv[1], "send")) {
    camo_wallet *wb = open_or_die(b);
    camo_wallet_add_subaddress(wb, "Bob's shop");
    uint32_t idx = camo_wallet_num_subaddresses(wb) - 1;
    char to[200]; snprintf(to, sizeof to, "%s", camo_wallet_address(wb, idx));
    printf("B subaddress #%u (%s): %s\n", idx, camo_wallet_subaddress_label(wb, idx), to);
    camo_wallet_close(wb, 1);
    camo_wallet *wa = open_or_die(a);
    sync_w(wa, argv[3]);
    if (!camo_wallet_prepare(wa, to, 5000000000000ULL, 0, 2)) { fprintf(stderr, "prepare: %s\n", camo_last_error()); camo_wallet_close(wa, 1); return 1; }
    printf("prepared amount %llu fee %llu\n", (unsigned long long)camo_wallet_prepared_amount(wa), (unsigned long long)camo_wallet_prepared_fee(wa));
    const char *txid = camo_wallet_commit(wa);
    if (!txid) { fprintf(stderr, "commit: %s\n", camo_last_error()); camo_wallet_close(wa, 1); return 1; }
    printf("txid %s\n", txid);
    camo_wallet_close(wa, 1);
    return 0;
  }
  if (!strcmp(argv[1], "check")) {
    camo_wallet *wb = open_or_die(b);
    sync_w(wb, argv[3]);
    camo_wallet_history_refresh(wb);
    for (int i = 0; i < camo_wallet_history_count(wb); i++) printf("row %s\n", camo_wallet_history_row(wb, i));
    camo_wallet_close(wb, 1);
    return 0;
  }
  return 2;
}

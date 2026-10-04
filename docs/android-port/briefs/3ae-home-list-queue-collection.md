# Brief 3ae: Add to Queue and Add to Collection on Home's section lists

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

A small one. On Home's "see all" lists
(`android/app/src/main/java/io/github/cidy02/kudos/home/HomeSectionListScreen.kt`, brief 3ab) a
row's menu offers **Add to Queue** and **Add to Collection**, and both do nothing: the screen
passes `onAddToQueue = {}` and `onAddToCollection = {}`.

The Library's lists have both, working. In `library/LibraryScreen.kt` the state
`addToQueueWorkId` / `addToCollectionWorkId` opens two `AlertDialog`s written inline in that
screen (search for `addToQueueWorkId?.let` and `addToCollectionWorkId?.let`): a list of queues
with "Manage queues", and a checklist of collections with a field to create one.

## Do this, and only this

1. Move those two dialogs out of `LibraryScreen` into shared composables in the `library`
   package (for example `library/WorkMembershipDialogs.kt`), taking what they need as
   parameters instead of reading the Library's view model. Keep every string, every button and
   every repository call exactly as it is. `LibraryScreen` then calls the shared composables:
   its behaviour must not change.
2. Use the same two composables on `HomeSectionListScreen`, wired to the repositories that
   screen already receives (`workRepository`, `queueRepository`, and the snapshot's queues and
   collections). If it lacks something the dialogs need, add a parameter with a default and pass
   it from `app/AppNavHost.kt`; say so in the result.
3. Don't change anything else on either screen.

## Result

Write `docs/android-port/briefs/3ae-result.md`: the two composables' signatures; every string in
them (unchanged from the Library's); each repository call before and after, on both screens; any
parameter you added.

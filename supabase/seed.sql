-- Demo seed data: fake and deterministic, never real people (CLAUDE.md §2 rule 7).
-- Fixed random seed so every `supabase db reset` produces the same demo data.
select setseed(0.2026);
